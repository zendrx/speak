require "./speak/*"

CONFIG_PATH = "./speak/config.json"

def main
  auto_setup = ARGV.includes?("--auto-setup")
  force_setup = ARGV.includes?("--setup")
  use_case = ARGV.includes?("--coding") ? "coding" : "general"
  if !File.exists?(CONFIG_PATH) || force_setup
    puts "speak - First time setup"
    puts "=" * 40

    manager = Speak::ModelManager.new(use_case)

    if auto_setup || force_setup
      success = manager.auto_setup
    else
      success = manager.setup
    end

    unless success
      puts "Setup failed. Exiting."
      exit 1
    end

    puts "\nSetup complete. Run ./speak-cli again to start chatting."
    exit 0
  end

  config = Speak::Config.load?
  unless config
    config = Speak::Config.load
  end
  settings = config.active
  detected = config.detected

  puts "speak - Local AI Assistant"
  puts "=" * 40
  puts "Hardware: #{detected.total_ram_mb} MB RAM, #{settings.cpu_cores} cores"
  puts "Model: #{settings.model_file}"
  puts "Context: #{settings.context_size} tokens"
  puts "=" * 40
  model_path = "./speak/models/#{settings.model_file}"

  unless File.exists?(model_path)
    puts "Model file not found: #{model_path}"
    puts "Downloading model..."

    installer = Speak::Install.new
    success = installer.install_model(settings.model_quant)

    unless success && File.exists?(model_path)
      puts "Failed to download model. Please check your internet connection."
      puts "You can also download the model manually and place it in: #{model_path}"
      exit 1
    end

    puts "Model downloaded successfully."
  end
  server = Speak::Server.new
  server.start

  if server.running?
    chat = Speak::Chat.new(settings)
  else
    server.start
  end
end

main
