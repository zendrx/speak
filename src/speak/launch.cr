module Speak
  class Launch
    def initialize(@context : Llama::Context, @settings : Speak::Setting)
      @history = [] of {role: String, content: String}
      @running = true
      @terminal_width = `tput cols`.to_i
      @column_width = (@terminal_width / 2) - 2
    end

    def run
      setup_terminal
      clear_screen
      show_header
      input_loop
      cleanup_terminal
    end

    private def input_loop
      while @running
        user_input = get_user_input
        
        break if user_input.downcase == "exit"
        break if user_input.downcase == "quit"
        
        next if user_input.strip.empty?
        
        @history << {role: "user", content: user_input}
        
        response = generate_response(user_input)
        @history << {role: "assistant", content: response}
        
        display_exchange(user_input, response)
      end
    end

    private def get_user_input : String
      print "\nYou: "
      input = gets || ""
      input.strip
    end

    private def generate_response(prompt : String) : String
      # Build context from history
      context_text = build_context
      full_prompt = "#{context_text}\n\nUser: #{prompt}\n\nAssistant:"
      
      # Generate response from model
      response = @context.generate(
        prompt: full_prompt,
        max_tokens: @settings.max_tokens,
        temperature: @settings.temperature
      )
      
      response.strip
    end

    private def build_context : String
      recent = @history.last(10)
      context = recent.map do |msg|
        role = msg[:role].capitalize
        "#{role}: #{msg[:content]}"
      end.join("\n")
      
      context
    end

    private def display_exchange(user_input : String, response : String)
      clear_screen
      show_header
      
      # Display conversation history
      @history.each_cons(2) do |pair|
        if pair.size == 2 && pair[0][:role] == "user"
          display_columns(pair[1][:content], pair[0][:content])
        end
      end
      
      # Display current exchange
      display_columns(response, user_input)
    end

    private def display_columns(model_response : String, user_prompt : String)
      model_lines = wrap_text(model_response, @column_width).split("\n")
      user_lines = wrap_text(user_prompt, @column_width).split("\n")
      
      max_lines = Math.max(model_lines.size, user_lines.size)
      
      puts "\n" + "Model Response".ljust(@column_width) + " | " + "Your Prompt"
      puts "-" * (@terminal_width - 1)
      
      max_lines.times do |i|
        model_line = model_lines[i]? || ""
        user_line = user_lines[i]? || ""
        
        model_text = model_line.ljust(@column_width)
        user_text = user_line.ljust(@column_width)
        
        puts "#{model_text} | #{user_text}"
      end
    end

    private def wrap_text(text : String, width : Int32) : String
      lines = [] of String
      current_line = ""
      
      text.split(/\s+/).each do |word|
        if (current_line + " " + word).size <= width
          current_line = current_line.empty? ? word : "#{current_line} #{word}"
        else
          lines << current_line if !current_line.empty?
          current_line = word
        end
      end
      
      lines << current_line if !current_line.empty?
      lines.join("\n")
    end

    private def show_header
      puts "\n" + "=" * (@terminal_width - 1)
      puts "Speak - Local LLM Chat Interface".center(@terminal_width)
      puts "Model: #{@settings.model_file} | Context: #{@settings.context_size}".center(@terminal_width)
      puts "=" * (@terminal_width - 1)
      puts "\nType 'exit' or 'quit' to close"
      puts ""
    end

    private def setup_terminal
      # Disable echo and enable raw mode for better input handling
      system("stty raw -echo") if system("which stty")
    end

    private def cleanup_terminal
      # Restore terminal settings
      system("stty -raw echo") if system("which stty")
      puts "\n\nGoodbye."
    end

    private def clear_screen
      print "\u001b[2J\u001b[H"
    end
  end
end
