require "http/client"
require "json"

module SpeakServer
  class Server
    def initialize(@model_path : String)
    end

    def start
      if running?
        puts "server is in an active state"
      else
        settings = config.active
        context_size = "#{settings.context_size}"
        args = [
          "-m", @model_path,
          "-port", "8080",
          "-c", settings,
          "--no-ui",
        ]
        @process = Process.new(
          "llama-server",
          args,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )

        wait_for_ready
      end
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
      raise "Server failed to start within #{timeout_seconds} seconds"
    end

    def stop?
      if running?
        @process.try &.signal(Signal::TERM)
        @process.try &.wait
      else
        puts "server not running"
      end
    end

    def running?
      @process.try &.exists? || false
    end
  end
end
