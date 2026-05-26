require "http/client"
require "json"

module Speak
  class Install
    CACHE_DIR      = "./speak/models"
    HFD_SCRIPT_URL = "https://hf-mirror.com/hfd/hfd.sh"
    HFD_PATH       = "./hfd.sh"

    MODEL_URLS = {
      "Q2_K" => {
        repo_id:  "mradermacher/Nanbeige4.1-3B-GGUF",
        filename: "Nanbeige4.1-3B.Q2_K.gguf",
        size_mb:  1700,
      },
      "Q4_K_M" => {
        repo_id:  "Edge-Quant/Nanbeige4.1-3B-Q4_K_M-GGUF",
        filename: "nanbeige4.1-3b-q4_k_m.gguf",
        size_mb:  2500,
      },
      "Q6_K" => {
        repo_id:  "mradermacher/Nanbeige4.1-3B-GGUF",
        filename: "Nanbeige4.1-3B.Q6_K.gguf",
        size_mb:  3300,
      },
    }

    def initialize
      Dir.mkdir_p(CACHE_DIR) unless Dir.exists?(CACHE_DIR)
    end

    def install_model(quant : String) : Bool
      unless MODEL_URLS.has_key?(quant)
        puts "Error: Unknown model quant '#{quant}'"
        puts "Available: #{MODEL_URLS.keys.join(", ")}"
        return false
      end

      model_info = MODEL_URLS[quant]
      dest_path = File.join(CACHE_DIR, model_info[:filename])

      if File.exists?(dest_path)
        actual_size = File.size(dest_path)
        expected_size = model_info[:size_mb].to_u64 * 1024 * 1024
        if actual_size >= expected_size - (1024 * 1024)
          puts "Model already exists: #{model_info[:filename]}"
          return true
        else
          puts "Existing file incomplete, re-downloading..."
          File.delete(dest_path) if File.exists?(dest_path)
        end
      end

      if !check_command("bash")
        puts "Error: bash is required but not found"
        return false
      end

      install_aria2_if_needed
      setup_hfd
      download_with_hfd(model_info[:repo_id], model_info[:filename], quant)

      if File.exists?(dest_path)
        puts "\nInstallation complete: #{model_info[:filename]}"
        true
      else
        puts "\nInstallation failed"
        false
      end
    end

    private def check_command(cmd : String) : Bool
      `which #{cmd} 2>/dev/null`.strip.empty? == false
    end

    private def install_aria2_if_needed
      return if check_command("aria2c")

      puts "\naria2c not found. Installing aria2 for faster downloads..."

      if check_command("apt")
        system("sudo apt install -y aria2")
      elsif check_command("yum")
        system("sudo yum install -y aria2")
      elsif check_command("dnf")
        system("sudo dnf install -y aria2")
      elsif check_command("pacman")
        system("sudo pacman -S --noconfirm aria2")
      elsif check_command("brew")
        system("brew install aria2")
      else
        puts "Warning: Could not install aria2. Will use fallback download."
      end
    end

    private def setup_hfd
      return if File.exists?(HFD_PATH) && File::Info.executable?(HFD_PATH)

      puts "Downloading hfd.sh..."
      system("wget -q -O #{HFD_PATH} #{HFD_SCRIPT_URL}")
      system("chmod a+x #{HFD_PATH}")
    end

    private def download_with_hfd(repo_id : String, filename : String, quant : String)
      puts "\nDownloading #{quant} model..."
      puts "This may take a few minutes depending on your connection.\n\n"

      ENV["HF_ENDPOINT"] = "https://hf-mirror.com"

      cmd = "bash #{HFD_PATH} #{repo_id} --include #{filename} --local-dir #{CACHE_DIR} --tool aria2c -x 16"
      system(cmd)

      unless File.exists?(File.join(CACHE_DIR, filename))
        puts "\nhfd failed, trying fallback download..."
        fallback_download(repo_id, filename)
      end
    end

    private def fallback_download(repo_id : String, filename : String)
      url = "https://huggingface.co/#{repo_id}/resolve/main/#{filename}"
      dest_path = File.join(CACHE_DIR, filename)

      headers = HTTP::Headers.new
      headers["User-Agent"] = "speak-installer/1.0"

      existing_size = File.exists?(dest_path) ? File.size(dest_path) : 0_u64

      if existing_size > 0
        headers["Range"] = "bytes=#{existing_size}-"
        puts "Resuming from #{format_bytes(existing_size.to_u64.to_u64)}"
      end

      begin
        HTTP::Client.get(url, headers) do |response|
          unless response.status_code == 200 || response.status_code == 206
            puts "HTTP #{response.status_code}: Failed to download"
            return
          end

          total_size = response.headers["Content-Length"]?.try(&.to_u64) || 0_u64
          total_size += existing_size

          File.open(dest_path, existing_size > 0 ? "ab" : "wb") do |file|
            buffer = Bytes.new(8192)
            downloaded = existing_size
            start_time = Time.instant

            while bytes_read = response.body_io.read(buffer)
              break if bytes_read == 0
              file.write(buffer[0, bytes_read])
              downloaded += bytes_read

              if total_size > 0
                percent = (downloaded * 100 / total_size).to_i
                elapsed = (Time.instant - start_time).total_seconds
                speed = elapsed > 0 ? (downloaded - existing_size).to_f / elapsed / (1024 * 1024) : 0
                print "\rProgress: #{percent}% | #{format_bytes(downloaded.to_u64)} / #{format_bytes(total_size.to_u64)} | #{speed.round(1)} MB/s"
                STDOUT.flush
              end
            end
          end
        end
        puts "\nFallback download completed"
      rescue ex
        puts "\nFallback download failed: #{ex.message}"
      end
    end

    private def format_bytes(bytes : UInt64) : String
      units = ["B", "KB", "MB", "GB"]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.size - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(1)} #{units[unit_index]}"
    end
  end
end
