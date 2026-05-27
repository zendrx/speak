# speak.cr - Main entry point for speak
# Integrates hardware detection, model selection, configuration, and chat

require "llama"
require "./speak/system"
require "./speak/config"
require "./speak/model"
require "./speak/install"
require "./speak/disk"
require "./speak/tool"
require "./speak/memory"
require "./speak/launch"

CONFIG_PATH = "./speak/config.json"

def main
  # Parse command line arguments
  auto_setup = ARGV.includes?("--auto-setup")
  force_setup = ARGV.includes?("--setup")
  use_case = ARGV.includes?("--coding") ? "coding" : "general"

  # Check if config exists and we're not forcing setup
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
    
    puts "\nSetup complete. Run ./speak again to start chatting."
    exit 0
  end

  # Load existing configuration
  config = Speak::Config.load?
  unless config
    puts "Error: Config file exists but cannot be loaded."
    puts "Please run: ./speak --setup"
    exit 1
  end

  settings = config.active
  detected = config.detected

  puts "speak - Local AI Assistant"
  puts "=" * 40
  puts "Hardware: #{detected.total_ram_mb} MB RAM, #{settings.cpu_cores} cores"
  puts "Model: #{settings.model_file}"
  puts "Context: #{settings.context_size} tokens"
  puts "=" * 40

  # Check if model file exists
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

  # Determine if we should use mmap based on available RAM
  use_mmap = settings.use_mmap && detected.available_ram_mb < 8000

  # Load the model
  puts "Loading model..."
  model = Llama::Model.new(model_path, use_mmap: use_mmap)
  
  # Create context
  context = Llama::Context.new(
    model: model,
    n_ctx: settings.context_size
  )

  # Launch chat interface
  puts "Starting chat interface..."
  puts "Type 'exit' to quit, 'help' for commands"
  puts "-" * 40
  
  launcher = Speak::Launch.new(context, model, settings)
  launcher.run
end

# Handle interrupt signals gracefully
Signal::INT.trap do
  puts "\n\nInterrupted. Goodbye."
  exit 0
end

Signal::TERM.trap do
  puts "\n\nTerminated. Goodbye."
  exit 0
end

# Run main function
main
