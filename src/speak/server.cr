require "http/client"
require "json"
require "tempfile"

module Speak
  class Server
    @[Embed("resources/bin/llama-server")]
    LLAMA_SERVER_BIN : String

    @process : Process?
    @port : String
    @settings : ActiveSettings
    @memories : Array(String)
    @memory_file : String
    @temp_bin_path : String?

    def initialize
      @port = "8080"
      config = Speak::Config.load
      @settings = config.active
      @memories = [] of String
      @memory_file = "./speak/memory.txt"
      @temp_bin_path = nil
    end

    def start
      if running?
        puts "server is in an active state"
        return
      end

      temp_bin = extract_binary
      @model_path = "./speak/models/#{@settings.model_file}"
      context_size = @settings.context_size

      args = [
        "-m", @model_path,
        "--host", "127.0.0.1",
        "--port", "8080",
        "-c", context_size.to_s,
        "--no-ui",
      ].compact

      @process = Process.new(
        temp_bin,
        args,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )

      wait_for_ready
    end

    private def extract_binary : String
      temp_file = File.tempfile("llama-server", "bin")
      temp_path = temp_file.path
      temp_file.close

      File.write(temp_path, LLAMA_SERVER_BIN, mode: "wb")
      File.chmod(temp_path, 0o755)

      @temp_bin_path = temp_path
      temp_path
    end

    def wait_for_ready
      seconds = 60
      timeout = Time.monotonic + seconds.seconds

      while Time.monotonic < timeout
        begin
          response = HTTP::Client.get("http://localhost:#{@port}/health")
          return true if response.status_code == 200
        rescue
          puts "server not ready"
        end
        sleep 0.5
      end

      raise "Server failed to start within #{seconds} seconds"
    end

    def stop?
      if running?
        @process.try &.signal(Signal::TERM)
        @process.try &.wait
        cleanup_temp_bin
      else
        puts "server not running"
      end
    end

    def running?
      @process.try &.exists? || false
    end

    def chat(message) : String
      if running?
        body = {
          model:       "local",
          messages:    message,
          temperature: "#{@settings.temperature}",
          max_tokens:  "#{@settings.max_tokens}",
          stream:      false,
        }.to_json

        response = HTTP::Client.post(
          "http://127.0.0.1:8080/v1/chat/completions",
          headers: HTTP::Headers{"Content-Type" => "application/json"},
          body: body
        )

        json = JSON.parse(response.body)
        content = json.dig("choices", 0, "message", "content").as_s
        call_tool(content)
      else
        return "server not running"
      end
    end

    def call_tool(content) : String
      lines = content.lines
      clean_lines = [] of String
      new_memories = [] of String

      lines.each do |line|
        if line.starts_with?("MEMORY:")
          memory = line[7..-1].strip
          new_memories << memory
        else
          clean_lines << line
        end
      end

      new_memories.each { |m| add(m) }
      save if !new_memories.empty?
      clean_lines.join("\n").strip
    end

    def add(text : String)
      return if text.empty?
      return if @memories.includes?(text)
      @memories << text
    end

    def save
      Dir.mkdir_p(File.dirname(@memory_file))
      File.write(@memory_file, @memories.join("\n"))
    end

    private def cleanup_temp_bin
      if path = @temp_bin_path
        if File.exists?(path)
          File.delete(path)
        end
        @temp_bin_path = nil
      end
    end
  end
end