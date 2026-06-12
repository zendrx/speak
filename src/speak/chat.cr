require "readline"
require "json"

module Speak
  class Chat
    @disk_cache : DiskCache
    @tool : Tool
    @memory : AgentMemory
    @settings : ActiveSettings
    @history : Array({role: String, content: String})
    @system_prompt : String

    def initialize
    end

    def run
      show_header
      input_loop
      save_conversation_history
      puts "\nGoodbye."
    end

    private def show_header
      clear_screen
      puts "=" * 70
      puts "speak - Local AI Assistant".center(70)
      puts "=" * 70
      puts "Model: #{@settings.model_file}"
      puts "Context: #{@settings.context_size} tokens"

      memory_content = @tool.load_user_memory
      memory_size = memory_content.bytesize
      puts "Memory: #{memory_size} bytes (#{memory_content.lines.size} lines)"

      puts "=" * 70
      puts "Commands: exit, clear, history, save, memory, clearmemory, reset"
      puts "Tools: read_file, search_web, remember, finish"
      puts "=" * 70
    end

    private def input_loop
      while @running
        print "\n> "
        input = Readline.readline("", true)
        input = input.to_s.strip

        if input.empty?
          next
        end

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
        when "memory"
          show_memory
        when "clearmemory"
          @tool.clear_memory
          @memory.clear_session
          puts "Memory cleared."
        when "reset"
          @memory.reset_working_memory
          puts "Working memory reset."
        else
          process_user_input(input)
        end
      end
    end

    private def process_user_input(input : String)
      @history << {role: "user", content: input}

      final_answer = agent_loop(input)

      @history << {role: "assistant", content: final_answer}
      @memory.save_episodic_memory(input, final_answer, "success")
      save_conversation_history

      puts "\nspeak: #{final_answer}"
    end
  end
end
