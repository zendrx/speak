module Speak
  module System
    def self.total_ram_mb : UInt64
      meminfo = File.read("/proc/meminfo")
      if match = meminfo.match(/MemTotal:\s+(\d+)/)
        return match[1].to_u64 // 1024
      end
      8192_u64
    end

    def self.available_ram_mb : UInt64
      meminfo = File.read("/proc/meminfo")
      if match = meminfo.match(/MemAvailable:\s+(\d+)/)
        return match[1].to_u64 // 1024
      end
      if match = meminfo.match(/MemFree:\s+(\d+)/)
        return match[1].to_u64 // 1024
      end
      4096_u64
    end

    def self.process_ram_mb : UInt64
      statm = File.read("/proc/self/statm")
      parts = statm.split
      if parts.size >= 2
        page_size = 4096_u64
        resident_pages = parts[1].to_u64
        return (resident_pages * page_size) // (1024 * 1024)
      end
      100_u64
    end

    def self.cpu_cores : Int32
      count = 0
      File.read("/proc/cpuinfo")
        .split("\n")
        .each do |line|
          if line.starts_with?("processor")
            count += 1
          end
        end
      if count > 4
        return 4
      end
      count > 0 ? count : 4
    end

    def self.cpu_has_avx2 : Bool
      cpuinfo = File.read("/proc/cpuinfo")
      if cpuinfo.includes?("avx2")
        return true
      end
      false
    end

    def self.free_disk_space_mb(path : String) : UInt64
      begin
        result = `df -B1 #{path} 2>/dev/null | tail -1`.strip
        parts = result.split
        if parts.size >= 4
          available = parts[3].to_u64? || 0_u64
          return available // (1024_u64 * 1024_u64)
        end
      rescue
      end
      0_u64
    end

    def self.ram_tier : Symbol
      total_ram = total_ram_mb
      case total_ram
      when 0..4096
        :ultra_low
      when 4096...6144
        :low
      when 6144...8192
        :medium
      else
        :high
      end
    end

    def self.os_reserved_ram_mb : UInt64
      total = total_ram_mb
      case total
      when 0..4096
        256_u64
      when 4096...6144
        512_u64
      when 6144...8192
        1024_u64
      else
        2048_u64
      end
    end

    def self.recommended_quant : String
      avail = available_ram_mb
      case avail
      when 0...3000
        "Q2_K"
      when 3000...6000
        "Q4_K_M"
      else
        "Q6_K"
      end
    end

    def self.recommended_context_size : Int32
      avail = available_ram_mb
      case avail
      when 0...3000
        512
      when 3000...6000
        1024
      else
        8192
      end
    end

    def self.model_file : String
      quant = recommended_quant
      case quant
      when "Q2_K"
        "nanbiege-3b-q2_k.gguf"
      when "Q4_K_M"
        "nanbiege-3b-q4_k_m.gguf"
      else
        "nanbiege-3b-q6_k.gguf"
      end
    end

    def self.kv_cache_type : String
      avail = available_ram_mb
      if avail < 6000
        "memory"
      else
        "disk"
      end
    end
  end
end
