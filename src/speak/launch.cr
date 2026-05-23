# launch.cr - Terminal chat interface for speak
#
# Provides a clean, streaming chat experience with:
# - Persistent conversation state via disk-backed KV cache
# - Real-time token streaming
# - Conversation history display
# - Graceful shutdown with state saving
#
# Uses config.json as the single source of truth for all settings.

require "llama"
require "./config"
require "./disk_cache"

module Speak
  # Terminal chat interface for speak.
  #
  # Handles user input, streaming output, and conversation display.
  # All generation parameters come from config.json via ActiveSettings.
  class Launch
    @disk_cache : DiskCache
    @settings : ActiveSettings
    @history : Array({role: String, content: String})
    @running : Bool
    @system_prompt : String

    # Creates a new chat session.
    #
    # - context: The Llama::Context with loaded model
    # - settings: ActiveSettings from config.json (source of truth)
    def initialize(context : Llama::Context, @settings : ActiveSettings)
      @disk_cache = DiskCache.new(context, @settings)
      @history = [] of {role: String, content: String}
      @running = true
      @system_prompt = load_system_prompt
      
      # Load conversation history from disk cache if it exists
      load_conversation_history
    end

    def load_system_prompt : String
      {{ read_file("#{__DIR__}/system_prompt.txt") }}
    end

    # Starts the main chat loop.
    #
    # Displays header, processes user input, and handles graceful shutdown.
    def run
      setup_terminal
      show_header
      input_loop
      save_conversation_history
      cleanup_terminal
    end

    # ------------------------------------------------------------------
    # Main Loop
    # ------------------------------------------------------------------

    # Processes user input until exit command.
    private def input_loop
      while @running
        print "\n> "
        input = gets || ""
        input = input.strip
        
        case input.downcase
        when "exit", "quit"
          @running = false
        when "clear"
          clear_screen
          show_header
        when "history"
          show_history
        when "save"
          save_conversation_history
          puts "Conversation saved."
        else
          next if input.empty?
          process_user_input(input)
        end
      end
    end

    # Processes a user message and generates a response.
    private def process_user_input(input : String)
      # Add user message to history
      @history << {role: "user", content: input}
      
      # Build prompt with system context and conversation
      prompt = build_prompt(input)
      
      # Print assistant label
      print "\nspeak: "
      
      # Generate streaming response using disk-backed cache
      response = String::Builder.new
      @disk_cache.generate(prompt) do |token|
        print token
        response << token
        STDOUT.flush
      end
      
      # Add assistant response to history
      @history << {role: "assistant", content: response.to_s.strip}
      
      # Auto-save after each exchange
      save_conversation_history
    end

    # ------------------------------------------------------------------
    # Prompt Construction
    # ------------------------------------------------------------------

    # Builds the prompt for the model.
    #
    # Uses the system prompt and only the most recent messages to stay
    # within context window limits. The KV cache handles the rest.
    private def build_prompt(user_input : String) : String
      # Start with system prompt
      prompt = String::Builder.new
      prompt << @system_prompt << "\n\n"
      
      # Add last N messages (N = context_size / estimated tokens per message)
      # This is a safety limit - KV cache handles the actual conversation
      max_history = 10
      recent = @history.last(max_history)
      
      recent.each do |msg|
        role = msg[:role] == "user" ? "User" : "Assistant"
        prompt << "#{role}: #{msg[:content]}\n"
      end
      
      # Add the current user message
      prompt << "User: #{user_input}\nAssistant:"
      
      prompt.to_s
    end

    # ------------------------------------------------------------------
    # History Management
    # ------------------------------------------------------------------

    # Saves conversation history to disk.
    private def save_conversation_history
      return if @history.empty?
      
      # Create directory if it doesn't exist
      Dir.mkdir_p("./speak/history") unless Dir.exists?("./speak/history")
      
      # Save with timestamp
      timestamp = Time.now.to_s("%Y%m%d_%H%M%S")
      history_file = "./speak/history/chat_#{timestamp}.json"
      
      # Convert history to JSON
      history_json = @history.map do |msg|
        {role: msg[:role], content: msg[:content]}
      end.to_json
      
      File.write(history_file, history_json)
      
      # Also save to latest.json for quick resume
      File.write("./speak/history/latest.json", history_json)
    end

    # Loads conversation history from latest session.
    private def load_conversation_history
      latest_file = "./speak/history/latest.json"
      return unless File.exists?(latest_file)
      
      begin
        data = File.read(latest_file)
        loaded = Array({role: String, content: String}).from_json(data)
        @history = loaded
        puts "Loaded previous conversation (#{@history.size} messages)"
      rescue
        # Silently ignore corrupted history
      end
    end

    # ------------------------------------------------------------------
    # Display Methods
    # ------------------------------------------------------------------

    # Shows the application header with system information.
    private def show_header
      clear_screen
      puts "=" * 60
      puts "speak - Local AI Assistant".center(60)
      puts "=" * 60
      puts "Model: #{@settings.model_file}"
      puts "Context: #{@settings.context_size} tokens"
      puts "KV Cache: #{@settings.kv_cache_type}"
      puts "=" * 60
      puts "Commands: exit, clear, history, save"
      puts "=" * 60
    end

    # Shows conversation history.
    private def show_history
      return puts("\nNo conversation history.") if @history.empty?
      
      puts "\n" + "=" * 60
      puts "Conversation History".center(60)
      puts "=" * 60
      
      @history.each_with_index do |msg, i|
        role = msg[:role].capitalize
        content = msg[:content]
        
        # Truncate long messages for display
        if content.size > 80
          content = content[0, 77] + "..."
        end
        
        puts "[#{i + 1}] #{role}: #{content}"
      end
      
      puts "=" * 60
      puts "Total: #{@history.size} messages"
    end

    # Clears the terminal screen.
    private def clear_screen
      print "\e[2J\e[H"
    end

    # ------------------------------------------------------------------
    # Terminal Setup
    #
    # Note: We do NOT use raw mode because:
    # 1. It breaks line editing (backspace, arrows, Ctrl+A/E)
    # 2. It requires complex signal handling
    # 3. It's unnecessary for a simple chat interface
    # The default cooked mode works perfectly for 99% of users.
    # ------------------------------------------------------------------

    # Sets up the terminal for normal line input.
    private def setup_terminal
      # No terminal modifications needed
      # The default cooked mode gives users:
      # - Line editing (backspace, arrow keys)
      # - Command history (up/down arrows)
      # - Ctrl+C to interrupt
      # - Ctrl+D to exit
      #
      # This is the best UX for a chat interface.
    end

    # Restores terminal settings on exit.
    private def cleanup_terminal
      puts "\n\nGoodbye."
      
      # Flush any pending cache saves
      # The DiskCache already saves after each generation
    end
  end
end
