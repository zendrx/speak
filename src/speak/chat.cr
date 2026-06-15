require "readline"
require "json"

module Speak
  class Chat
    @system_prompt : String
    @settings : ActiveSettings
    @@history = [] of NamedTuple(role: String, content: String)

    def initialize(settings)
      @settings = settings
      @system_prompt = system_prompt
      start
    end

    def start
      show_header
      input_loop
      puts "\nGoodbye."
    end

    private def show_header
      clear_screen
      puts "=" * 70
      puts "speak - Local AI Assistant".center(70)
      puts "=" * 70
      puts "Model: #{@settings.model_file}"
      puts "Context: #{@settings.context_size} tokens"
      puts "=" * 70
      puts "Commands: exit, clear"
      puts "=" * 70
    end

    private def input_loop
      while @@running
        print "\n> "
        input = Readline.readline("", true)
        input = input.to_s.strip

        if input.empty?
          next
        end

        case input.downcase
        when "exit", "quit"
          @@running = false
        when "clear"
          clear_screen
          show_header
        else
          if !Dir.exists?("./speak")
            @@history << {role: "system", content: @system_prompt}
            process_user_input(input)
          else
            process_user_input(input)
          end
        end
      end
    end

    private def process_user_input(input : String)
      final_answer = agent_loop(input)
      @@history << {role: "assistant", content: final_answer}
      puts "\nspeak: #{final_answer}"
    end

    private def system_prompt : String
      runtime_prompt_path = "./speak/system_prompt"
      default_prompt = {{ read_file("#{__DIR__}/system_prompt.txt") }}
      unless File.exists?(runtime_prompt_path)
        File.write(runtime_prompt_path, default_prompt)
        puts "No system prompt found. Created default at #{runtime_prompt_path}"
      end

      prompt = File.read(runtime_prompt_path)
    end

    private def agent_loop(input : String)
      @@history << {role: "user", content: input}
      chat = send_to_server
      return chat
    end

    private def send_to_server : String
      chat = Speak::Server.new
      chat.chat(@@history)
    end

    private def clear_screen
      print "\e[2J\e[H"
    end
  end
end
