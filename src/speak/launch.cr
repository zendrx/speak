# launch.cr - Terminal chat interface for speak

require "llama"
require "./config"
require "./disk_cache"
require "./tool"

module Speak
  class Launch
    @disk_cache : DiskCache
    @tool : Tool
    @settings : ActiveSettings
    @history : Array({role: String, content: String})
    @running : Bool
    @system_prompt : String

    def initialize(context : Llama::Context, @settings : ActiveSettings)
      @disk_cache = DiskCache.new(context, @settings)
      @tool = Tool.new
      @history = [] of {role: String, content: String}
      @running = true
      @system_prompt = load_system_prompt
      load_conversation_history
    end

    def run
      setup_terminal
      show_header
      input_loop
      save_conversation_history
      cleanup_terminal
    end

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

    private def process_user_input(input : String)
      @history << {role: "user", content: input}

      prompt = build_prompt(input)

      print "\nspeak: "
      response = String::Builder.new

      @disk_cache.generate(prompt) do |token|
        print token
        response << token
        STDOUT.flush
      end

      full_response = response.to_s.strip

      full_response = @tool.process_tool_calls(full_response)

      @history << {role: "assistant", content: full_response}
      save_conversation_history
    end

    private def build_prompt(user_input : String) : String
      prompt = String::Builder.new
      prompt << @system_prompt << "\n\n"

      user_memory = @tool.memory_for_prompt
      prompt << user_memory << "\n" unless user_memory.empty?

      max_history = 10
      recent = @history.last(max_history)

      recent.each do |msg|
        role = msg[:role] == "user" ? "User" : "Assistant"
        prompt << "#{role}: #{msg[:content]}\n"
      end

      prompt << "User: #{user_input}\nAssistant:"

      prompt.to_s
    end

    private def load_system_prompt : String
      {{ read_file("#{__DIR__}/system_prompt.txt") }}
    end

    private def save_conversation_history
      return if @history.empty?

      Dir.mkdir_p("./speak/history") unless Dir.exists?("./speak/history")

      timestamp = Time.now.to_s("%Y%m%d_%H%M%S")
      history_file = "./speak/history/chat_#{timestamp}.json"

      history_json = @history.map do |msg|
        {role: msg[:role], content: msg[:content]}
      end.to_json

      File.write(history_file, history_json)
      File.write("./speak/history/latest.json", history_json)
    end

    private def load_conversation_history
      latest_file = "./speak/history/latest.json"
      return unless File.exists?(latest_file)

      begin
        data = File.read(latest_file)
        loaded = Array({role: String, content: String}).from_json(data)
        @history = loaded
        puts "Loaded previous conversation (#{@history.size} messages)"
      rescue
      end
    end

    private def show_header
      clear_screen
      puts "=" * 60
      puts "speak - Local AI Assistant".center(60)
      puts "=" * 60
      puts "Model: #{@settings.model_file}"
      puts "Context: #{@settings.context_size} tokens"
      puts "KV Cache: #{@settings.kv_cache_type}"
      puts "Memory: #{@tool.load_user_memory.size} bytes"
      puts "=" * 60
      puts "Commands: exit, clear, history, save"
      puts "Tools: <read>file</read>, <memory>fact</memory>"
      puts "=" * 60
    end

    private def show_history
      return puts("\nNo conversation history.") if @history.empty?

      puts "\n" + "=" * 60
      puts "Conversation History".center(60)
      puts "=" * 60

      @history.each_with_index do |msg, i|
        role = msg[:role].capitalize
        content = msg[:content]

        if content.size > 80
          content = content[0, 77] + "..."
        end

        puts "[#{i + 1}] #{role}: #{content}"
      end

      puts "=" * 60
      puts "Total: #{@history.size} messages"
    end

    private def clear_screen
      print "\e[2J\e[H"
    end

    private def setup_terminal
    end

    private def cleanup_terminal
      puts "\n\nGoodbye."
    end
  end
end
