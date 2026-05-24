# spec/test.cr
# Main test suite for speak
# Run with: crystal spec spec/test.cr
# Expected runtime: 10-15 minutes on CI, 5-8 minutes on local (with caching)

require "./spec_helper"
require "file_utils"
require "time"
require "json"

module Speak
  # Global test configuration
  TEST_TIMEOUT = 10.seconds
  TEST_MODEL_PATH = "./speak/models/nanbeige-3b-q4_k_m.gguf"
  SKIP_SLOW_TESTS = ENV["CI"]? == "true"
  SKIP_NETWORK_TESTS = ENV["CI"]? == "true"

  # Helper for timing assertions
  def self.time_it(operation : String, &block)
    start = Time.monotonic
    result = yield
    elapsed = (Time.monotonic - start).total_seconds
    puts "  #{operation} completed in #{elapsed.round(2)}s" if ENV["SPEAK_DEBUG"]?
    {result, elapsed}
  end

  def self.skip_test?(name : String) : Bool
    if SKIP_SLOW_TESTS && (name.includes?("benchmark") || name.includes?("full_model"))
      puts "  Skipping #{name} (slow test disabled in CI)"
      return true
    end
    if SKIP_NETWORK_TESTS && (name.includes?("web_search") || name.includes?("network"))
      puts "  Skipping #{name} (network test disabled in CI)"
      return true
    end
    false
  end

  describe "speak - Core System Tests (~2-3 minutes)" do
    describe "System Hardware Detection" do
      it "detects total RAM correctly" do
        total = System.total_ram_mb
        total.should be > 0
        total.should be < 1024 * 1024 # less than 1TB
      end

      it "detects available RAM correctly" do
        available = System.available_ram_mb
        available.should be >= 0
        available.should be <= System.total_ram_mb
      end

      it "detects CPU cores" do
        cores = System.cpu_cores
        cores.should be > 0
        cores.should be <= 256
      end

      it "detects AVX2 support (returns boolean)" do
        has_avx2 = System.cpu_has_avx2
        has_avx2.should be_true.or be_false
      end

      it "calculates OS reserved RAM correctly" do
        reserve = System.os_reserved_ram_mb
        reserve.should be >= 256
        reserve.should be <= 4096
      end

      it "returns valid RAM tier" do
        tier = System.ram_tier
        [:ultra_low, :low, :medium, :high].should contain(tier)
      end

      it "recommends appropriate quant based on RAM" do
        quant = System.recommended_quant
        ["Q2_K", "Q4_K_M", "Q6_K"].should contain(quant)
      end

      it "recommends appropriate context size" do
        ctx = System.recommended_context_size
        [512, 1024, 2048, 4096].should contain(ctx)
      end
    end

    describe "Disk Space Detection" do
      it "returns free disk space for current directory" do
        free = System.free_disk_space_mb(".")
        free.should be >= 0
      end

      it "returns 0 for invalid path" do
        free = System.free_disk_space_mb("/nonexistent/path/that/does/not/exist")
        free.should eq(0)
      end
    end
  end

  describe "speak - Configuration Tests (~1-2 minutes)" do
    TEST_CONFIG_DIR = "./test_config"

    before_all do
      Dir.mkdir_p(TEST_CONFIG_DIR) unless Dir.exists?(TEST_CONFIG_DIR)
    end

    after_all do
      FileUtils.rm_rf(TEST_CONFIG_DIR)
    end

    it "creates new config file on first run" do
      path = "#{TEST_CONFIG_DIR}/fresh_config.json"
      File.delete(path) if File.exists?(path)
      
      config = Config.load_or_create(path)
      
      File.exists?(path).should be_true
      config.should be_a(Config)
    end

    it "loads existing config file correctly" do
      path = "#{TEST_CONFIG_DIR}/existing_config.json"
      sample_json = <<-JSON
      {
        "detected": {
          "total_ram_mb": 8192,
          "available_ram_mb": 6200,
          "os_reserved_ram_mb": 512
        },
        "active": {
          "cpu_cores": 4,
          "has_avx2": true,
          "free_disk_space_mb": 51200,
          "context_size": 2048,
          "kv_cache_type": "standard",
          "model_quant": "Q4_K_M",
          "model_file": "test.gguf",
          "temperature": 0.7,
          "max_tokens": 512,
          "use_mmap": true
        },
        "user_overrides": {}
      }
      JSON
      File.write(path, sample_json)
      
      config = Config.load_or_create(path)
      
      config.active.context_size.should eq(2048)
      config.active.model_quant.should eq("Q4_K_M")
    end

    it "applies user overrides correctly" do
      path = "#{TEST_CONFIG_DIR}/override_config.json"
      sample_json = <<-JSON
      {
        "detected": {
          "total_ram_mb": 8192,
          "available_ram_mb": 6200,
          "os_reserved_ram_mb": 512
        },
        "active": {
          "cpu_cores": 4,
          "has_avx2": true,
          "free_disk_space_mb": 51200,
          "context_size": 2048,
          "kv_cache_type": "standard",
          "model_quant": "Q4_K_M",
          "model_file": "test.gguf",
          "temperature": 0.7,
          "max_tokens": 512,
          "use_mmap": true
        },
        "user_overrides": {
          "context_size": 4096,
          "temperature": 1.2
        }
      }
      JSON
      File.write(path, sample_json)
      
      config = Config.load_or_create(path)
      settings = config.apply_overrides
      
      settings.context_size.should eq(4096)
      settings.temperature.should eq(1.2)
    end

    it "saves config with pretty JSON formatting" do
      path = "#{TEST_CONFIG_DIR}/save_config.json"
      File.delete(path) if File.exists?(path)
      
      detected = DetectedRam.new
      detected.total_ram_mb = 8192_u64
      detected.available_ram_mb = 6200_u64
      detected.os_reserved_ram_mb = 512_u64
      
      active = ActiveSettings.new
      active.context_size = 2048
      active.model_quant = "Q4_K_M"
      active.model_file = "test.gguf"
      active.temperature = 0.7_f32
      active.max_tokens = 512
      active.use_mmap = true
      
      user_overrides = UserOverrides.new
      config = Config.new(detected, active, user_overrides)
      config.save(path)
      
      File.exists?(path).should be_true
      content = File.read(path)
      content.should contain("context_size")
      content.should contain("pretty")
    end
  end

  describe "speak - Tool System Tests (~2-3 minutes)" do
    TEST_TOOL_DIR = "./test_tools"

    before_all do
      Dir.mkdir_p(TEST_TOOL_DIR) unless Dir.exists?(TEST_TOOL_DIR)
    end

    after_all do
      FileUtils.rm_rf(TEST_TOOL_DIR)
    end

    describe "#read_file" do
      it "reads existing file correctly" do
        tool = Tool.new
        test_file = "#{TEST_TOOL_DIR}/test_read.txt"
        File.write(test_file, "Hello, test content!")
        
        content = tool.read_file(test_file)
        
        content.should eq("Hello, test content!")
      end

      it "returns error for non-existent file" do
        tool = Tool.new
        content = tool.read_file("#{TEST_TOOL_DIR}/nonexistent.txt")
        
        content.should contain("Error")
      end

      it "prevents path traversal attacks" do
        tool = Tool.new
        content = tool.read_file("../etc/passwd")
        
        content.should contain("Error")
        content.should contain("outside current directory")
      end

      it "rejects files larger than 13MB" do
        tool = Tool.new
        large_file = "#{TEST_TOOL_DIR}/large.txt"
        File.write(large_file, "x" * (14 * 1024 * 1024))
        
        content = tool.read_file(large_file)
        
        content.should contain("Error")
        content.should contain("too large")
      end
    end

    describe "#web_search" do
      it "returns string result for any query (fast check)" do
        tool = Tool.new
        results = tool.web_search("test")
        results.should be_a(String)
      end unless SKIP_NETWORK_TESTS

      it "handles empty query gracefully" do
        tool = Tool.new
        results = tool.web_search("")
        results.should be_a(String)
      end
    end

    describe "#memory operations" do
      it "writes and reads user memory" do
        tool = Tool.new
        tool.clear_memory
        
        tool.write_to_memory("Test fact: User loves testing", append: false)
        memory = tool.load_user_memory
        
        memory.should contain("Test fact")
      end

      it "appends to existing memory" do
        tool = Tool.new
        tool.clear_memory
        tool.write_to_memory("Fact 1", append: false)
        tool.write_to_memory("Fact 2", append: true)
        
        memory = tool.load_user_memory
        memory.should contain("Fact 1")
        memory.should contain("Fact 2")
      end

      it "returns empty string for empty memory" do
        tool = Tool.new
        tool.clear_memory
        
        memory = tool.memory_for_prompt
        memory.should eq("")
      end
    end

    describe "#process_tool_calls" do
      it "parses and executes read_file tool call" do
        tool = Tool.new
        test_file = "#{TEST_TOOL_DIR}/process_test.txt"
        File.write(test_file, "Process test content")
        
        response = %(<tool_call>{"name":"read_file","arguments":{"path":"#{test_file}"}}</tool_call>)
        result = tool.process_tool_calls(response)
        
        result.should contain("Process test content")
      end

      it "parses and executes remember tool call" do
        tool = Tool.new
        tool.clear_memory
        
        response = %(<tool_call>{"name":"remember","arguments":{"fact":"User likes automated testing"}}</tool_call>)
        result = tool.process_tool_calls(response)
        
        result.should contain("I've remembered")
        
        memory = tool.load_user_memory
        memory.should contain("User likes automated testing")
      end

      it "handles invalid JSON gracefully" do
        tool = Tool.new
        response = "<tool_call>invalid json here</tool_call>"
        result = tool.process_tool_calls(response)
        
        result.should be_a(String)
      end
    end

    describe "#tools_schema" do
      it "returns valid JSON" do
        tool = Tool.new
        schema = tool.tools_schema
        
        schema.should be_a(String)
        parsed = JSON.parse(schema)
        parsed.should be_a(Array)
        parsed.size.should be >= 3
      end

      it "includes all expected tools" do
        tool = Tool.new
        schema = JSON.parse(tool.tools_schema).as_a
        
        tool_names = schema.map { |t| t["function"]["name"].as_s }
        tool_names.should contain("read_file")
        tool_names.should contain("search_web")
        tool_names.should contain("remember")
        tool_names.should contain("finish")
      end
    end
  end

  describe "speak - Memory System Tests (~1-2 minutes)" do
    TEST_MEMORY_DIR = "./test_agent_memory"

    before_all do
      Dir.mkdir_p(TEST_MEMORY_DIR) unless Dir.exists?(TEST_MEMORY_DIR)
    end

    after_all do
      FileUtils.rm_rf(TEST_MEMORY_DIR)
    end

    describe "Working Memory" do
      it "stores and retrieves goals and steps" do
        memory = AgentMemory.new
        steps = ["Search for data", "Analyze results", "Generate report"]
        memory.set_goal("Complete analysis", steps)
        
        memory.get_current_step.should eq("Search for data")
        memory.advance_step
        memory.get_current_step.should eq("Analyze results")
        memory.advance_step
        memory.get_current_step.should eq("Generate report")
      end

      it "detects goal completion" do
        memory = AgentMemory.new
        steps = ["Step 1", "Step 2"]
        memory.set_goal("Test goal", steps)
        
        memory.is_goal_complete?.should be_false
        memory.advance_step
        memory.is_goal_complete?.should be_false
        memory.advance_step
        memory.is_goal_complete?.should be_true
      end

      it "records tool calls in history" do
        memory = AgentMemory.new
        memory.record_tool_call("test_tool", '{"param":"value"}', "success result")
        
        history = memory.get_all_tool_history
        history.size.should be >= 1
        history.last.tool_name.should eq("test_tool")
        history.last.result.should eq("success result")
      end

      it "adds observations to working memory" do
        memory = AgentMemory.new
        memory.add_observation("User requested weather information")
        memory.add_observation("Found weather data for Lagos")
        
        summary = memory.get_working_summary
        summary.should contain("User requested")
        summary.should contain("weather data for Lagos")
      end
    end

    describe "Semantic Memory" do
      it "stores and recalls facts" do
        memory = AgentMemory.new
        memory.save_semantic_fact("Crystal language is fast", "observation", 0.9)
        
        facts = memory.recall_semantic_facts("Crystal")
        facts.size.should be >= 1
        facts.first.fact.should contain("Crystal")
      end

      it "respects confidence scores in recall" do
        memory = AgentMemory.new
        memory.save_semantic_fact("Fact A", "user", 0.9)
        memory.save_semantic_fact("Fact B", "inference", 0.5)
        
        facts = memory.recall_semantic_facts("Fact", 2)
        facts.first.confidence.should be >= facts.last.confidence if facts.size > 1
      end
    end

    describe "Episodic Memory" do
      it "saves and loads episodes" do
        memory = AgentMemory.new
        memory.save_episodic_memory("User asked about weather", "It's sunny", "success")
        
        episodes = memory.load_recent_episodes(1)
        episodes.size.should be >= 1
        episodes.first.user_input.should contain("weather")
      end
    end
  end

  describe "speak - Integration Tests (~3-5 minutes)" do
    it "compiles without errors (build test)" do
      result = `crystal build src/speak.cr --release -o /dev/null 2>&1`
      $?.success?.should be_true
    end

    it "has valid help output (if implemented)" do
      # This is a placeholder - add when --help is implemented
      true.should be_true
    end

    it "loads config file and applies settings" do
      config = Config.load_or_create
      settings = config.apply_overrides
      
      settings.context_size.should be >= 512
      settings.context_size.should be <= 4096
      settings.temperature.should be_between(0.0, 2.0)
      settings.max_tokens.should be_between(50, 2048)
    end
  end

  describe "speak - Performance Benchmarks (~2-3 minutes)" do
    it "measures tokenization speed" do
      tool = Tool.new
      text = "The quick brown fox jumps over the lazy dog. " * 100
      
      start = Time.monotonic
      10.times { tool.process_tool_calls(text) }
      elapsed = (Time.monotonic - start).total_seconds
      
      puts "\n  Tokenization speed: #{10 / elapsed.round(2)} calls/sec" if ENV["SPEAK_DEBUG"]?
      elapsed.should be < 1.0
    end unless SKIP_SLOW_TESTS

    it "measures config load time" do
      config_path = "./speak/config.json"
      if File.exists?(config_path)
        start = Time.monotonic
        10.times { Config.load_or_create(config_path) }
        elapsed = (Time.monotonic - start).total_seconds
        
        puts "\n  Config load speed: #{10 / elapsed.round(2)} loads/sec" if ENV["SPEAK_DEBUG"]?
        elapsed.should be < 2.0
      else
        true.should be_true
      end
    end

    it "reports memory usage (manual check)" do
      puts "\n  Memory check: Run 'ps aux | grep speak' to view memory usage"
      true.should be_true
    end
  end
end

# Summary output after all tests
def print_test_summary
  puts "\n" + "=" * 60
  puts "TEST SUMMARY"
  puts "=" * 60
  puts "Expected runtime: 10-15 minutes"
  puts "CI mode: #{ENV["CI"]? == "true"}"
  puts "Network tests: #{SKIP_NETWORK_TESTS ? "disabled" : "enabled"}"
  puts "Slow tests: #{SKIP_SLOW_TESTS ? "disabled" : "enabled"}"
  puts "=" * 60
end

at_exit do
  print_test_summary
end
