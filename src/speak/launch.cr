require "llama"
require "readline"
require "json"
require "./config"
require "./disk"
require "./tool"
require "./memory"

module Speak
  class Launch
    @disk_cache : DiskCache
    @tool : Tool
    @memory : AgentMemory
    @settings : ActiveSettings
    @history : Array({role: String, content: String})
    @running : Bool
    @system_prompt : String
    @max_iterations : Int32 = 10

    def initialize(context : Llama::Context, model : Llama::Model, @settings : ActiveSettings)
      @disk_cache = DiskCache.new(context, model.vocab, @settings)
      @tool = Tool.new
      @memory = AgentMemory.new
      @history = [] of {role: String, content: String}
      @running = true
      @system_prompt = load_system_prompt
      load_conversation_history
    end

    def run
      show_header
      input_loop
      save_conversation_history
      puts "\nGoodbye."
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

    private def agent_loop(user_input : String) : String
      messages = build_initial_messages(user_input)
      iteration = 0

      while iteration < @max_iterations
        prompt = build_prompt_from_messages(messages)
        response = generate_response(prompt)

        tool_result = @tool.process_tool_calls(response)

        if tool_result[:handled]
          messages << {role: "assistant", content: response}
          messages << {role: "tool", content: tool_result[:result]}

          if tool_result[:result].starts_with?("FINISH:")
            return tool_result[:result].gsub("FINISH:", "")
          end

          observation = "Tool result: #{tool_result[:result]}"
          @memory.add_observation(observation)
          @memory.record_tool_call(
            extract_tool_name(response),
            extract_tool_args(response),
            tool_result[:result]
          )
          iteration += 1
        else
          @memory.save_episodic_memory(user_input, response, "success")
          return response
        end
      end

      "I've exceeded my maximum attempts. Please try a simpler request."
    end

    private def build_initial_messages(user_input : String) : Array({role: String, content: String})
      messages = [] of {role: String, content: String}

      system_content = String::Builder.new
      system_content << @system_prompt << "\n\n"
      system_content << "## Available Tools\n"
      system_content << @tool.tools_schema << "\n\n"
      system_content << "## Tool Usage Format\n"
      system_content << "When you need to use a tool, output:\n"
      system_content << "<tool_call>{\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}</tool_call>\n\n"
      system_content << "After receiving tool results, continue your response.\n"
      system_content << "When you have the complete answer, call the finish tool.\n\n"

      user_memory = @tool.memory_for_prompt
      if !user_memory.empty?
        system_content << user_memory << "\n"
      end

      agent_memory = @memory.build_memory_prompt
      if !agent_memory.empty?
        system_content << agent_memory << "\n"
      end

      messages << {role: "system", content: system_content.to_s}
      messages << {role: "user", content: user_input}

      messages
    end

    private def build_prompt_from_messages(messages : Array({role: String, content: String})) : String
      prompt = String::Builder.new

      messages.each do |msg|
        case msg[:role]
        when "system"
          prompt << msg[:content] << "\n\n"
        when "user"
          prompt << "User: " << msg[:content] << "\n"
        when "assistant"
          prompt << "Assistant: " << msg[:content] << "\n"
        when "tool"
          prompt << "Tool Result: " << msg[:content] << "\n"
        end
      end

      prompt << "Assistant: "
      prompt.to_s
    end

    private def generate_response(prompt : String) : String
      response = ""
      @disk_cache.generate(prompt) do |token|
        response += token
      end
      response.strip
    end

    private def extract_tool_name(response : String) : String
      if match = /"name":\s*"([^"]+)"/.match(response)
        return match[1].to_s
      end
      "unknown"
    end

    private def extract_tool_args(response : String) : String
      if match = /"arguments":\s*(\{[^}]+\})/.match(response)
        return match[1].to_s
      end
      "{}"
    end

    private def load_system_prompt : String
      runtime_prompt_path = "./speak/system_prompt"
      default_prompt =  {{ read_file("#{__DIR__}/system_prompt.txt") }}
      unless File.exists?(runtime_prompt_path)
       # assuming the dir has been created and is writable, save the default prompt there
        File.write(runtime_prompt_path, default_prompt)
        puts "No system prompt found. Created default at #{runtime_prompt_path}"
      end

      File.read(runtime_prompt_path)
    end


    end

    private def save_conversation_history
      return if @history.empty?

      Dir.mkdir_p("./speak/history") unless Dir.exists?("./speak/history")

      timestamp = Time.utc.to_s("%Y%m%d_%H%M%S")
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
        puts "\n[Loaded previous conversation with #{@history.size} messages]"
      rescue
      end
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

    private def show_history
      return puts("\nNo conversation history.") if @history.empty?

      puts "\n" + "=" * 70
      puts "Conversation History".center(70)
      puts "=" * 70

      @history.each_with_index do |msg, i|
        role = msg[:role].capitalize
        content = msg[:content]

        if content.size > 80
          content = content[0, 77] + "..."
        end

        puts "[#{i + 1}] #{role}: #{content}"
      end

      puts "=" * 70
      puts "Total: #{@history.size} messages"
    end

    private def show_memory
      user_memory = @tool.load_user_memory

      if user_memory.empty?
        puts "\nNo user memory stored yet."
      else
        puts "\n" + "=" * 70
        puts "User Memory".center(70)
        puts "=" * 70
        puts user_memory
        puts "=" * 70
      end

      agent_memory = @memory.build_memory_prompt
      if !agent_memory.empty?
        puts "\n" + "=" * 70
        puts "Agent Working Memory".center(70)
        puts "=" * 70
        puts agent_memory
        puts "=" * 70
      end

      puts "\nMemory file: #{Tool::MEMORY_FILE}"
    end

    private def clear_screen
      print "\e[2J\e[H"
    end
  end
end
