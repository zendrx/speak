require "llama"
require "./speak/system"
require "./speak/config"
require "./speak/install"
require "./speak/launch"

def main
  config = Speak::Config.load_or_create
  settings = config.apply_overrides

  model_path = "./speak/models/#{settings.model_file}"
  
  model = if File.exists?(model_path)
    puts "Loading model: #{model_path}"
    Llama::Model.new(model_path)
  else
    puts "Model file not found: #{model_path}, installing..."
    installer = Speak::Install.new
    installer.install_model(settings.model_quant)
    
    if File.exists?(model_path)
      puts "Model installed successfully: #{model_path}"
      Llama::Model.new(model_path)
    else
      puts "Failed to install model: #{model_path}"
      exit(1)
    end
  end

  begin
    context = Llama::Context.new(
      model: model,
      n_ctx: settings.context_size,
      kv_cache_type: settings.kv_cache_type
    )
    launcher = Speak::Launch.new(context, settings)
    launcher.run
  rescue ex : Exception
    puts "Error: #{ex.message}"
    exit(1)
  end
end

main