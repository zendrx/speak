# model.cr - Model registry and selection for speak
# Handles displaying available models, user selection, and saving to config

require "json"
require "file_utils"

module Speak
  # Represents a single model in the registry
  struct ModelInfo
    include JSON::Serializable

    property id : String
    property name : String
    property description : String
    property params_b : Float64
    property quantization : String
    property weight_gb : Float64
    property kv_per_1k_gb : Float64
    property max_context_k : Int32
    property min_ram_gb : Int32
    property recommended_ram_gb : Int32
    property use_cases : Array(String)
    property quality_score : Int32
    property speed_score : Int32
    property multimodal : Bool
    property url : String
    property filename : String
    property mmproj_url : String?
    property mmproj_filename : String?
    property license : String
    property author : String
  end

  # Recommendation for a user
  struct ModelRecommendation
    include JSON::Serializable

    property model : ModelInfo
    property fit_score : Float64
    property speed_score : Float64
    property total_score : Float64
    property context_fits : Bool

    def initialize(@model, @fit_score, @speed_score, @total_score, @context_fits)
    end
  end

  class ModelManager
    # Models are embedded at compile time using read_file macro
    MODELS_JSON = {{ read_file("#{__DIR__}/models.json").chomp.stringify }}

    @registry : Array(ModelInfo)
    @available_ram_gb : Float64
    @total_ram_gb : Float64
    @use_case : String

    def initialize(available_ram_mb : UInt64, total_ram_mb : UInt64, use_case : String = "general")
      @available_ram_gb = available_ram_mb.to_f / 1024.0
      @total_ram_gb = total_ram_mb.to_f / 1024.0
      @use_case = use_case
      @registry = load_registry
    end

    # Load model registry from embedded JSON
    private def load_registry : Array(ModelInfo)
      Array(ModelInfo).from_json(MODELS_JSON)
    rescue ex
      puts "Error loading embedded model registry: #{ex.message}"
      puts "Falling back to empty registry"
      [] of ModelInfo
    end

    # Get models that fit in available RAM
    def get_compatible_models : Array(ModelInfo)
      @registry.select { |m| m.min_ram_gb <= @available_ram_gb }
    end

    # Calculate how well a model fits the user's RAM
    private def calculate_fit_score(model : ModelInfo) : Float64
      headroom = @available_ram_gb - model.weight_gb
      if headroom <= 0
        return 0.0
      elsif headroom >= 2.0
        return 1.0
      else
        return headroom / 2.0
      end
    end

    # Calculate expected speed based on model size and user's RAM
    private def calculate_speed_score(model : ModelInfo) : Float64
      base_speed = (3.0 / model.params_b).clamp(0.3, 1.0)
      ram_factor = [@available_ram_gb / model.weight_gb, 2.0].min
      ram_penalty = ram_factor / 2.0
      model_speed_factor = model.speed_score.to_f / 100.0
      base_speed * ram_penalty * model_speed_factor
    end

    # Calculate quality score (normalized from model's quality_score)
    private def calculate_quality_score(model : ModelInfo) : Float64
      model.quality_score.to_f / 100.0
    end

    # Score a model for the user's use case
    private def score_for_use_case(model : ModelInfo) : Float64
      if model.use_cases.includes?(@use_case)
        return 1.0
      elsif model.use_cases.includes?("general") || model.use_cases.includes?("chat")
        return 0.6
      else
        return 0.3
      end
    end

    # Get ranked recommendations
    def get_recommendations(limit : Int32 = 5) : Array(ModelRecommendation)
      compatible = get_compatible_models
      recommendations = [] of ModelRecommendation

      compatible.each do |model|
        fit_score = calculate_fit_score(model)
        speed_score = calculate_speed_score(model)
        quality_score = calculate_quality_score(model)
        use_case_score = score_for_use_case(model)

        total_score = (fit_score * 0.3) + (speed_score * 0.2) + (quality_score * 0.3) + (use_case_score * 0.2)
        context_fits = model.max_context_k >= 4096

        recommendations << ModelRecommendation.new(
          model, fit_score, speed_score, total_score, context_fits
        )
      end

      recommendations.sort_by! { |r| -r.total_score }
      recommendations.first(limit)
    end

    # Display models to user and get selection
    def interactive_selection : ModelInfo?
      recommendations = get_recommendations(8)
      
      if recommendations.empty?
        puts "No models found that fit your system (available RAM: #{@available_ram_gb.round(1)} GB)"
        puts "You can still try downloading a model manually to ./speak/models/"
        return nil
      end

      puts "\n" + "=" * 70
      puts "Model Selection for speak"
      puts "=" * 70
      puts "Your system: #{@total_ram_gb.round(1)} GB total, #{@available_ram_gb.round(1)} GB available"
      puts "Use case: #{@use_case}"
      puts "-" * 70
      puts ""

      recommendations.each_with_index do |rec, i|
        model = rec.model
        quality_stars = "★" * (model.quality_score / 20).to_i + "☆" * (5 - (model.quality_score / 20).to_i)
        speed_stars = "★" * (model.speed_score / 20).to_i + "☆" * (5 - (model.speed_score / 20).to_i)
        
        puts "#{i + 1}. #{model.name}"
        puts "   Size: #{model.weight_gb.round(1)} GB | Quality: #{quality_stars} | Speed: #{speed_stars}"
        puts "   #{model.description}"
        puts "   Use cases: #{model.use_cases.join(", ")}"
        puts "   License: #{model.license} | Author: #{model.author}"
        puts ""
      end

      print "Select model [1-#{recommendations.size}] or 'a' for auto (best match): "
      input = gets.chomp.strip

      if input.downcase == "a"
        best = recommendations.first
        puts "\nAuto-selected: #{best.model.name}"
        return best.model
      end

      index = input.to_i - 1
      if index >= 0 && index < recommendations.size
        return recommendations[index].model
      else
        puts "Invalid selection. Please run again."
        return nil
      end
    end

    # Save selected model to config
    def save_to_config(model : ModelInfo, config_path : String = "./speak/config.json")
      unless File.exists?(config_path)
        puts "Config file not found. Run speak once to generate it first."
        return false
      end

      begin
        config_data = File.read(config_path)
        config = JSON.parse(config_data)
        
        # Update active settings with selected model
        config.as_h["active"] = {
          "context_size" => [model.max_context_k, 4096].min,
          "model_quant" => model.quantization,
          "model_file" => model.filename,
          "temperature" => 0.7,
          "max_tokens" => 512,
          "use_mmap" => true,
          "cpu_cores" => config.as_h["active"]["cpu_cores"],
          "has_avx2" => config.as_h["active"]["has_avx2"],
          "free_disk_space_mb" => config.as_h["active"]["free_disk_space_mb"],
          "kv_cache_type" => "standard"
        }
        
        File.write(config_path, config.to_pretty_json)
        puts "\nModel saved to config: #{model.name}"
        puts "You can now run ./speak"
        return true
      rescue ex
        puts "Error updating config: #{ex.message}"
        return false
      end
    end
  end
end
