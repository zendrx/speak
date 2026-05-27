# disk.cr - Disk-backed KV cache for speak
#
# Implements ds4-style optimization where KV cache lives on SSD instead of RAM.
# Uses Llama::State from llama.cr for all state operations.
#
# Cache keys are SHA1 of token IDs (little-endian 32-bit integers), matching
# ds4's exact specification. This ensures deterministic, collision-resistant
# keys that align with what the model actually consumes.
#
# Only streaming generation is supported - tokens appear as they are generated
# for the best user experience.

require "llama"
require "digest/sha1"
require "json"
require "./config"

module Speak
  # Disk-backed KV cache manager for persistent conversation state.
  #
  # This class wraps a Llama::Context and automatically manages saving and
  # loading of KV cache to disk. All generation parameters come from the
  # config.json source of truth.
  #
  # Cache files are named `<sha1>.kv` and stored in `./speak/kv_cache/`.
  # LRU cleanup removes old caches when the maximum count is exceeded.
  #
  # Only streaming generation is supported - tokens are yielded as they arrive.
  #
  # ## Example
  # ```
  # context = Llama::Context.new(model)
  # cache = Speak::DiskCache.new(context, settings)
  #
  # cache.generate("Hello, who are you?") do |token|
  #   print token
  # end
  # ```
  class DiskCache
    # Directory where KV cache files are stored
    CACHE_DIR = "./speak/kv_cache"

    # Maximum number of cache files to keep (LRU cleanup)
    MAX_CACHE_FILES = 50

    @state : Llama::State
    @context : Llama::Context
    @settings : ActiveSettings
    @cache_metadata : Hash(String, CacheMetadata)
    @metadata_file : String
    @token_history : Array(Int32)

    # Metadata for each cached conversation.
    #
    # Used for LRU cleanup and cache management.
    struct CacheMetadata
      include JSON::Serializable

      # Last access time as Unix timestamp
      property access_time : Int64
      # Number of tokens in the conversation
      property token_count : Int32
      # Creation time as Unix timestamp
      property created_at : Int64

      def initialize(@access_time, @token_count, @created_at = Time.utc.to_unix)
      end
    end

    # Creates a new DiskCache instance.
    #
    # Creates the cache directory if it doesn't exist, loads existing metadata,
    # and performs initial cleanup if needed.
    #
    # - context: The Llama::Context to wrap with disk caching
    # - settings: The ActiveSettings from config.json (source of truth)
    def initialize(@context : Llama::Context, @vocab : Llama::Vocab, @settings : ActiveSettings)
      Dir.mkdir_p(CACHE_DIR) unless Dir.exists?(CACHE_DIR)

      @state = Llama::State.new(@context)
      @metadata_file = File.join(CACHE_DIR, "metadata.json")
      @cache_metadata = load_metadata
      @token_history = [] of Int32

      cleanup_if_needed
    end

    # Generates a streaming response using disk-backed KV cache.
    #
    # Automatically:
    # 1. Calculates a cache key from the prompt using ds4's SHA1 token ID method
    # 2. Loads any existing cache from disk (if available)
    # 3. Generates the response (extending KV cache)
    # 4. Saves the updated cache back to disk
    #
    # Uses max_tokens and temperature from config.json.
    #
    # - prompt: The user input to generate a response for
    # - Yields each token as a string as it is generated
    def generate(prompt : String, &)
      cache_key = cache_key_for(prompt)
      cache_path = cache_path_for(cache_key)

      # Load existing cache from disk if available
      if File.exists?(cache_path)
        if load_cache(cache_path)
          update_metadata_access(cache_key)
        end
      end

      # Track tokens for state saving
      @token_history.clear

      # Generate with streaming - tokens appear in real time
      response = @context.generate(
        prompt,
        max_tokens: @settings.max_tokens,
        temperature: @settings.temperature.to_f32
      )

      tokens = @vocab.tokenize(prompt)
      @token_history = tokens

      save_cache(cache_path, cache_key)

      response
    end

    # Clears all cached KV files and metadata.
    #
    # Frees disk space used by the cache. Does not affect the current
    # conversation state in memory.
    def clear_cache
      Dir.glob("#{CACHE_DIR}/*.kv").each do |file|
        File.delete(file)
      end
      Dir.glob("#{CACHE_DIR}/*.meta.json").each do |file|
        next if File.basename(file) == "metadata.json"
        File.delete(file)
      end
      @cache_metadata.clear
      save_metadata
    end

    # Clears cache for a specific conversation.
    #
    # - cache_key: The SHA1 key of the conversation to clear
    def clear_conversation(cache_key : String)
      cache_path = cache_path_for(cache_key)
      File.delete(cache_path) if File.exists?(cache_path)
      @cache_metadata.delete(cache_key)
      save_metadata
    end

    # Total disk space used by cache in megabytes.
    #
    # Returns the sum of sizes of all .kv files in the cache directory.
    def cache_size_mb : UInt64
      total = 0_u64
      Dir.glob("#{CACHE_DIR}/*.kv").each do |file|
        total += File.size(file)
      end
      total / (1024 * 1024)
    end

    # Number of cached conversations.
    def cache_count : Int32
      @cache_metadata.size
    end

    # Lists all cached conversations with their metadata.
    #
    # Returns an array of tuples containing (cache_key, metadata).
    def list_caches : Array({String, CacheMetadata})
      @cache_metadata.map { |key, meta| {key, meta} }
    end

    # Returns the current token sequence length.
    #
    # Useful for debugging and monitoring conversation length.
    def current_token_count : Int32
      @token_history.size
    end

    # ------------------------------------------------------------------
    # Private Methods
    # ------------------------------------------------------------------

    # Generates a cache key following ds4's exact specification.
    #
    # ds4 uses SHA1 of token IDs (each token as little-endian 32-bit integer),
    # NOT raw text. This ensures the cache key matches what the model actually
    # consumes, avoiding BPE boundary misalignment issues.
    #
    # Files are named <sha1>.kv, matching ds4's naming convention.
    #
    # - context: The Llama::Context (needed for tokenization)
    # - prompt: The raw user input string
    # - Returns: SHA1 hex digest of the token ID sequence
    private def cache_key_for(prompt : String) : String
      # 1. Tokenize the prompt using the model's tokenizer
      #    This produces the exact token IDs the model will process
      token_ids = @vocab.tokenize(prompt)

      # 2. Create a buffer for little-endian 32-bit integers
      #    ds4 hashes each token ID as a little-endian u32
      io = IO::Memory.new
      token_ids.each do |token_id|
        # Write as 32-bit little-endian (same as ds4's "LE u32")
        io.write_bytes(token_id.to_u32, IO::ByteFormat::LittleEndian)
      end

      # 3. Return SHA1 hex digest (ds4 uses SHA1, not SHA256)
      #    Files are named <sha1>.kv
      Digest::SHA1.hexdigest(io.to_slice)
    end

    # Returns the file path for a given cache key.
    #
    # ds4 uses .kv extension for cache files.
    private def cache_path_for(cache_key : String) : String
      File.join(CACHE_DIR, "#{cache_key}.kv")
    end

    # Loads KV cache from disk using Llama::State.
    #
    # Returns true if the cache was loaded successfully, false otherwise.
    # Corrupted cache files are automatically deleted to prevent future errors.
    private def load_cache(path : String) : Bool
      return false unless File.exists?(path)
      return false if File.size(path) == 0

      # Load the state from disk using context_size from config
      # Destination context size must be >= source context size
      tokens = @state.load_file(path, @settings.context_size)

      # Synchronize our token history with loaded state
      @token_history = tokens.dup

      !tokens.empty?
    rescue ex
      STDERR.puts "Warning: Failed to load cache from #{path}: #{ex.message}"
      File.delete(path) if File.exists?(path)
      false
    end

    # Saves KV cache to disk using Llama::State.
    #
    # Requires the current token sequence to properly save the conversation state.
    private def save_cache(path : String, cache_key : String)
      success = @state.save_file(path, @token_history)

      if success
        # Update or create metadata for this cache
        @cache_metadata[cache_key] = CacheMetadata.new(
          access_time: Time.utc.to_unix,
          token_count: @token_history.size
        )
        save_metadata
      end
    rescue ex
      STDERR.puts "Warning: Failed to save cache to #{path}: #{ex.message}"
    end

    # Updates the access time for a cached conversation.
    private def update_metadata_access(cache_key : String)
      if meta = @cache_metadata[cache_key]?
        meta.access_time = Time.utc.to_unix
        save_metadata
      end
    end

    # Loads metadata from disk.
    #
    # Returns an empty hash if the metadata file doesn't exist or is corrupted.
    private def load_metadata : Hash(String, CacheMetadata)
      return {} of String => CacheMetadata unless File.exists?(@metadata_file)

      begin
        data = File.read(@metadata_file)
        Hash(String, CacheMetadata).from_json(data)
      rescue
        {} of String => CacheMetadata
      end
    end

    # Saves metadata to disk.
    private def save_metadata
      File.write(@metadata_file, @cache_metadata.to_json)
    end

    # Removes old cache files if the maximum limit is exceeded.
    #
    # Uses least-recently-used (LRU) strategy based on access_time.
    private def cleanup_if_needed
      return unless @cache_metadata.size > MAX_CACHE_FILES

      # Sort by access time (oldest first)
      sorted = @cache_metadata.to_a.sort_by { |_, meta| meta.access_time }

      # Remove oldest until we're under the limit
      to_remove = sorted[0...(@cache_metadata.size - MAX_CACHE_FILES)]
      to_remove.each do |key, _|
        cache_path = cache_path_for(key)
        File.delete(cache_path) if File.exists?(cache_path)
        @cache_metadata.delete(key)
      end

      save_metadata
    end
  end
end
