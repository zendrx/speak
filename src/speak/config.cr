require "json"

module Speak
  # Represents the detected hardware (read from config.json)
  struct DetectedRam
    include JSON::Serializable

    property total_ram_mb : UInt64
    property available_ram_mb : UInt64
    property os_reserved_ram_mb : UInt64
  end

  # Represents the active settings (read from config.json)
  struct ActiveSettings
    include JSON::Serializable

    property cpu_cores : Int32
    property has_avx2 : Bool
    property free_disk_space_mb : UInt64
    property context_size : Int32
    property kv_cache_type : String
    property model_quant : String
    property model_file : String
    property temperature : Float64
    property max_tokens : Int32
    property use_mmap : Bool
  end

  # Configuration loader
  class Config
    include JSON::Serializable

    property detected : DetectedRam
    property active : ActiveSettings

    def initialize(@detected, @active)
    end

    # Load config from JSON file
    def self.load(path : String = "./speak/config.json") : Config
      unless File.exists?(path)
        raise "Config file not found: #{path}"
      end

      json = File.read(path)
      Config.from_json(json)
    end

    # Load config or return nil if not found
    def self.load?(path : String = "./speak/config.json") : Config?
      return nil unless File.exists?(path)
      
      begin
        json = File.read(path)
        Config.from_json(json)
      rescue ex
        puts "Error loading config: #{ex.message}"
        nil
      end
    end
  end
end
