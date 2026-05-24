require "json"
require "http/client"
require "uri"

module Speak
  class Tool
    MEMORY_DIR = "./speak/memory"
    MEMORY_FILE = "./speak/memory/user.md"
    SEARCH_TIMEOUT = 30.seconds
    MAX_SEARCH_RESULTS = 10

    @memory_cache : String?

    TOOLS_SCHEMA = [
      {
        "type": "function",
        "function": {
          "name": "read_file",
          "description": "Read the contents of a local file. Returns the file content as text.",
          "parameters": {
            "type": "object",
            "properties": {
              "path": {
                "type": "string",
                "description": "The file path to read (relative or absolute within current directory)"
              }
            },
            "required": ["path"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "search_web",
          "description": "Search the web for current information. Returns up to 10 results with titles, URLs, and snippets.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string",
                "description": "The search query to find information on the web"
              }
            },
            "required": ["query"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "remember",
          "description": "Store a fact about the user in long-term memory. This fact will be remembered across all future conversations.",
          "parameters": {
            "type": "object",
            "properties": {
              "fact": {
                "type": "string",
                "description": "The fact to remember (e.g., 'User name is Sarah', 'User prefers short answers')"
              }
            },
            "required": ["fact"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "finish",
          "description": "Call this tool when you have completed the user's request and are ready to provide the final answer.",
          "parameters": {
            "type": "object",
            "properties": {
              "final_answer": {
                "type": "string",
                "description": "The complete final answer to the user's request"
              }
            },
            "required": ["final_answer"]
          }
        }
      }
    ]

    def initialize
      Dir.mkdir_p(MEMORY_DIR) unless Dir.exists?(MEMORY_DIR)
      ensure_memory_file_exists
    end

    def tools_schema : String
      TOOLS_SCHEMA.to_json
    end

    def process_tool_calls(response : String) : {handled: Bool, result: String}
      tool_pattern = /<tool_call>\s*\{\s*"name":\s*"([^"]+)"\s*,\s*"arguments":\s*(\{[^}]+\})\s*\}\s*<\/tool_call>/
      if match = tool_pattern.match(response)
        tool_name = match[1].to_s
        arguments_json = match[2].to_s
        tool_result = execute_tool(tool_name, arguments_json)
        return {handled: true, result: tool_result}
      end
      {handled: false, result: response}
    end

    def execute_tool(name : String, arguments_json : String) : String
      begin
        args = JSON.parse(arguments_json)
        
        case name
        when "read_file"
          path = args["path"].as_s
          read_file(path)
        when "search_web"
          query = args["query"].as_s
          web_search(query)
        when "remember"
          fact = args["fact"].as_s
          write_to_memory(fact, append: true)
          "I've remembered: #{fact}"
        when "finish"
          final_answer = args["final_answer"].as_s
          "FINISH:#{final_answer}"
        else
          "Error: Unknown tool '#{name}'"
        end
      rescue ex
        "Error executing tool #{name}: #{ex.message}"
      end
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

    def web_search(query : String) : String
      encoded_query = URI.encode_www_form(query)
      url = "https://html.duckduckgo.com/html/?q=#{encoded_query}"

      begin
        client = HTTP::Client.new("html.duckduckgo.com", tls: true)
        client.read_timeout = SEARCH_TIMEOUT
        client.connect_timeout = SEARCH_TIMEOUT

        response = client.get("/html/?q=#{encoded_query}", headers: HTTP::Headers{
          "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
          "Accept" => "text/html,application/xhtml+xml",
          "Accept-Language" => "en-US,en;q=0.9",
        })

        client.close

        if response.status_code == 200
          results = parse_search_results(response.body)
          if results.empty?
            return "No results found for: #{query}"
          end
          return format_search_results(results, query)
        else
          return "Search failed with HTTP status: #{response.status_code}"
        end
      rescue ex : IO::TimeoutError
        return "Search timed out after #{SEARCH_TIMEOUT.total_seconds} seconds. Please try a more specific query."
      rescue ex
        return "Search error: #{ex.message}"
      end
    end

    private def parse_search_results(html : String) : Array({title: String, url: String, snippet: String})
      results = [] of {title: String, url: String, snippet: String}

      title_pattern = /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/
      snippet_pattern = /<a[^>]*class="result__snippet"[^>]*>([^<]+)<\/a>/

      titles = [] of {url: String, title: String}
      html.scan(title_pattern) do |match|
        url = match[1].to_s
        title = match[2].to_s.gsub(/<\/?[^>]*>/, "").strip
        if !url.empty? && !title.empty? && !url.includes?("duckduckgo.com")
          titles << {url: url, title: title}
        end
      end

      snippets = [] of String
      html.scan(snippet_pattern) do |match|
        snippet = match[1].to_s.gsub(/<\/?[^>]*>/, "").strip
        snippets << snippet if !snippet.empty?
      end

      titles.each_with_index do |item, i|
        snippet = i < snippets.size ? snippets[i] : ""
        results << {title: item[:title], url: item[:url], snippet: snippet}
        break if results.size >= MAX_SEARCH_RESULTS
      end

      results
    end

    private def format_search_results(results : Array({title: String, url: String, snippet: String}), query : String) : String
      output = String::Builder.new
      output << "Search results for: #{query}\n\n"

      results.each_with_index do |result, i|
        output << "#{i + 1}. #{result[:title]}\n"
        output << "   URL: #{result[:url]}\n"
        output << "   #{result[:snippet]}\n\n"
      end

      output << "---\n"
      output << "Found #{results.size} result(s). Use these to answer the user's question.\n"

      output.to_s
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

    def memory_for_prompt : String
      memory = load_user_memory
      return "" if memory.empty?

      <<-MEMORY
## Information I know about the user:
#{memory}

Note: This information was provided by the user in previous conversations.
To update this information, use the remember tool.

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
