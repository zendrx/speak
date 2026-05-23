require "json"

module Speak
  class Tool
    MEMORY_DIR = "./speak/memory"
    MEMORY_FILE = "./speak/memory/user.md"

    @memory_cache : String?

    def initialize
      Dir.mkdir_p(MEMORY_DIR) unless Dir.exists?(MEMORY_DIR)
      ensure_memory_file_exists
    end

    def process_tool_calls(response : String) : String
      result = response.dup

      if match = result.match(/<read>(.*?)<\/read>/m)
        file_path = match[1].strip
        file_content = read_file(file_path)
        result = result.gsub(/<read>.*?<\/read>/m, file_content)
      end

      if match = result.match(/<memory>(.*?)<\/memory>/m)
        memory_content = match[1].strip
        write_to_memory(memory_content, append: false)
        result = result.gsub(/<memory>.*?<\/memory>/m, "I've remembered that.")
      end

      if match = result.match(/<memory append>(.*?)<\/memory append>/m)
        memory_content = match[1].strip
        write_to_memory(memory_content, append: true)
        result = result.gsub(/<memory append>.*?<\/memory append>/m, "I've updated my memory.")
      end

      result
    end

    def read_file(path : String) : String
      if path.includes?("..")
        return "Error: Cannot read files outside the current directory."
      end

      full_path = File.expand_path(path)

      cwd = File.expand_path(".")
      unless full_path.starts_with?(cwd)
        return "Error: Cannot read files outside the current directory."
      end

      unless File.exists?(full_path)
        return "Error: File not found: #{path}"
      end

      unless File.file?(full_path)
        return "Error: Path is a directory, not a file: #{path}"
      end

      file_size = File.size(full_path)
      if file_size > 13 * 1024 * 1024
        return "Error: File too large (#{file_size / (1024 * 1024)}MB). Maximum 13MB."
      end

      begin
        content = File.read(full_path)
        return content
      rescue ex
        return "Error: Could not read file: #{ex.message}"
      end
    end

    def load_user_memory : String
      if File.exists?(MEMORY_FILE)
        content = File.read(MEMORY_FILE)
        @memory_cache = content
        return content
      end
      ""
    end

    def write_to_memory(content : String, append : Bool = false)
      if append && File.exists?(MEMORY_FILE)
        File.open(MEMORY_FILE, "a") do |file|
          file.puts "\n#{content}"
        end
      else
        File.write(MEMORY_FILE, content)
      end
      @memory_cache = nil
    end

    def append_fact(fact : String)
      timestamp = Time.now.to_s("%Y-%m-%d %H:%M:%S")
      File.open(MEMORY_FILE, "a") do |file|
        file.puts "\n[#{timestamp}] #{fact}"
      end
      @memory_cache = nil
    end

    def memory_for_prompt : String
      memory = load_user_memory
      return "" if memory.empty?

      <<-MEMORY
## Information I know about the user:
#{memory}

Note: This information was provided by the user in previous conversations.
To update this information, output <memory>new fact</memory> or <memory append>additional fact</memory append>.

      MEMORY
    end

    def clear_memory
      File.delete(MEMORY_FILE) if File.exists?(MEMORY_FILE)
      @memory_cache = nil
    end

    private def ensure_memory_file_exists
      return if File.exists?(MEMORY_FILE)

      header = <<-HEADER
# User Memory File for speak
# 
# This file contains information the AI has learned about you.
# You can edit this file directly to add, remove, or correct facts.
# The AI will read this file at the start of every conversation.
#
# Format: Use plain text. Each line is a separate fact.
# Example:
# Name: Sarah
# Role: Software Engineer
# Preference: Prefers concise answers
#
HEADER
      File.write(MEMORY_FILE, header)
    end
  end
end
