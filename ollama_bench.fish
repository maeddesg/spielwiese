#!/usr/bin/fish

function ollama_bench
    set model "qwen3-coder:30b"
    set card_path "/sys/class/drm/card1/device"

    # Check dependencies
    if not command -q jq
        echo "Error: jq is not installed"
        return 1
    end

    if not command -q curl
        echo "Error: curl is not installed"
        return 1
    end

    # Check if Ollama is running
    if not curl -s http://localhost:11434/api/tags >/dev/null 2>&1
        echo "Error: Ollama is not running (port 11434)"
        return 1
    end

    # Auto-detect backend
    if pacman -Qq ollama-vulkan &>/dev/null
        set backend "vulkan"
    else if pacman -Qq ollama-rocm &>/dev/null
        set backend "rocm"
    else
        set backend "cpu"
    end

    # Ollama version
    set ollama_version (ollama --version | string replace "ollama version is " "")

    set csv_file "benchmark_$backend.csv"

    # Memory files (early, for baseline)
    set vram_used_file "$card_path/mem_info_vram_used"
    set gtt_used_file "$card_path/mem_info_gtt_used"

    # Stop model for clean VRAM baseline
    echo "Stopping model $model for clean baseline..."
    ollama stop "$model" 2>/dev/null
    sleep 2

    # Measure VRAM/GTT baseline (without model = Firefox, compositor, etc.)
    if test -f "$vram_used_file"
        set baseline_vram_raw (cat "$vram_used_file")
        set baseline_vram_mb (math -s0 "$baseline_vram_raw / 1048576")
    else
        set baseline_vram_mb "N/A"
    end
    if test -f "$gtt_used_file"
        set baseline_gtt_raw (cat "$gtt_used_file")
        set baseline_gtt_mb (math -s0 "$baseline_gtt_raw / 1048576")
    else
        set baseline_gtt_mb "N/A"
    end

    # Reload model
    echo "Loading model $model..."
    curl -s -X POST http://localhost:11434/api/generate \
        -d "{\"model\": \"$model\", \"prompt\": \"hi\", \"stream\": false}" >/dev/null

    # Measure VRAM/GTT after loading
    if test -f "$vram_used_file"
        set loaded_vram_raw (cat "$vram_used_file")
        set loaded_vram_mb (math -s0 "$loaded_vram_raw / 1048576")
    else
        set loaded_vram_mb "N/A"
    end
    if test -f "$gtt_used_file"
        set loaded_gtt_raw (cat "$gtt_used_file")
        set loaded_gtt_mb (math -s0 "$loaded_gtt_raw / 1048576")
    else
        set loaded_gtt_mb "N/A"
    end

    # Calculate delta (actual model footprint)
    if test "$baseline_vram_mb" != "N/A"; and test "$loaded_vram_mb" != "N/A"
        set delta_vram_mb (math -s0 "$loaded_vram_mb - $baseline_vram_mb")
    else
        set delta_vram_mb "N/A"
    end
    if test "$baseline_gtt_mb" != "N/A"; and test "$loaded_gtt_mb" != "N/A"
        set delta_gtt_mb (math -s0 "$loaded_gtt_mb - $baseline_gtt_mb")
    else
        set delta_gtt_mb "N/A"
    end

    # Get model info
    set model_info (ollama ps 2>/dev/null | grep "$model")
    if test -n "$model_info"
        set model_size_num (echo "$model_info" | awk '{print $3}')
        set model_size_unit (echo "$model_info" | awk '{print $4}')
        set model_size "$model_size_num"_"$model_size_unit"
        set processor_raw (echo "$model_info" | awk '{print $5}')
        # Split percentages (e.g. "23%/77%" -> "23% (RAM) / 77% (VRAM)")
        set cpu_pct (echo "$processor_raw" | string split "/" | head -n 1)
        set gpu_pct (echo "$processor_raw" | string split "/" | tail -n 1)
        set model_processor "$cpu_pct (RAM) / $gpu_pct (VRAM)"
        # GPU percent as number for VRAM calculation (e.g. "77%" -> 77)
        set gpu_pct_num (echo "$gpu_pct" | string replace "%" "")
        # Convert model size to MB
        if test "$model_size_unit" = "GB"
            set model_size_mb (math "$model_size_num * 1024")
        else
            set model_size_mb "$model_size_num"
        end
        # Calculate model VRAM (model size x GPU%)
        set model_vram_mb (math -s0 "$model_size_mb * $gpu_pct_num / 100")
    else
        set model_size "N/A"
        set model_processor "N/A"
        set model_vram_mb "N/A"
    end

    # GPU clock file
    set sclk_file "$card_path/pp_dpm_sclk"

    # GPU utilization files
    set gpu_busy_file "$card_path/gpu_busy_percent"
    set mem_busy_file "$card_path/mem_busy_percent"

    # Memory files (total)
    set vram_total_file "$card_path/mem_info_vram_total"
    set gtt_total_file "$card_path/mem_info_gtt_total"

    # Read VRAM/GTT total once
    if test -f "$vram_total_file"
        set vram_total_raw (cat "$vram_total_file")
        set vram_total_mb (math -s0 "$vram_total_raw / 1048576")
    else
        set vram_total_mb "N/A"
    end
    if test -f "$gtt_total_file"
        set gtt_total_raw (cat "$gtt_total_file")
        set gtt_total_mb (math -s0 "$gtt_total_raw / 1048576")
    else
        set gtt_total_mb "N/A"
    end

    # Write CSV header if new
    if not test -f "$csv_file"
        echo "timestamp,ollama_version,backend,model,model_size,gpu_offload,tokens_per_sec,vram_mb,power_w,temp_c,ttft_ms,gpu_clock_mhz,vram_used_mb,gtt_used_mb,efficiency_tpw,vram_baseline_mb,gtt_baseline_mb,gpu_busy_pct,mem_busy_pct,warmup,prompt_tokens_per_sec" > "$csv_file"
    end

    echo "==============================================="
    echo "  Ollama Benchmark"
    echo "==============================================="
    echo "Ollama:  $ollama_version"
    echo "Backend: $backend"
    echo "Model:   $model"
    echo "Size:    $model_size"
    echo "Offload: $model_processor"
    echo "VRAM:    $vram_total_mb MB total | Baseline: $baseline_vram_mb MB | Model: +$delta_vram_mb MB | Loaded: $loaded_vram_mb MB"
    echo "GTT:     $gtt_total_mb MB total | Baseline: $baseline_gtt_mb MB | Model: +$delta_gtt_mb MB | Loaded: $loaded_gtt_mb MB"
    echo "CSV:     $csv_file"
    echo "-------------------------------------------------------------------------------------------------------------------"
    echo "Time     | Gen t/s | Prompt t/s | VRAM    | Power | Temp  | Clock   | GTT     | t/W   | GPU%  | MEM%  |"
    echo "-------------------------------------------------------------------------------------------------------------------"

    # Warmup counter (first run = warmup)
    set run_count 0

    # Power file
    set hwmon_files $card_path/hwmon/hwmon*/power1_average
    set power_file "$hwmon_files[1]"

    # Temperature file
    set temp_files $card_path/hwmon/hwmon*/temp1_input
    set temp_file_path "$temp_files[1]"

    # Clean exit on Ctrl+C
    function _cleanup --on-signal INT --on-signal TERM
        # Stop background sampler if active
        if set -q _power_sampler_pid
            kill $_power_sampler_pid 2>/dev/null
        end
        echo ""
        echo "Benchmark finished."
        exit 0
    end

    while true
        set run_count (math "$run_count + 1")
        if test "$run_count" -eq 1
            set is_warmup "true"
        else
            set is_warmup "false"
        end

        # Temp file for power sampling
        set power_samples_file (mktemp)

        # Sample files
        set clock_samples_file (mktemp)
        set gtt_samples_file (mktemp)
        set gpu_busy_samples_file (mktemp)
        set mem_busy_samples_file (mktemp)

        # Background sampler (every 100ms)
        if test -f "$power_file"
            fish -c "
                while true
                    cat '$power_file' >> '$power_samples_file'
                    if test -f '$sclk_file'
                        grep '\*' '$sclk_file' | string match -r '\d+(?=Mhz)' >> '$clock_samples_file'
                    end
                    if test -f '$gtt_used_file'
                        cat '$gtt_used_file' >> '$gtt_samples_file'
                    end
                    if test -f '$gpu_busy_file'
                        cat '$gpu_busy_file' >> '$gpu_busy_samples_file'
                    end
                    if test -f '$mem_busy_file'
                        cat '$mem_busy_file' >> '$mem_busy_samples_file'
                    end
                    sleep 0.1
                end
            " &
            set _power_sampler_pid $last_pid
        end

        # Run inference
        set response (curl -s -X POST http://localhost:11434/api/generate \
            -d "{\"model\": \"$model\", \"prompt\": \"Write a performant C++ function that inverts a binary tree.\", \"stream\": false}")

        # Stop sampler
        if set -q _power_sampler_pid
            kill $_power_sampler_pid 2>/dev/null
            set -e _power_sampler_pid
        end

        set eval_count (echo "$response" | jq -r '.eval_count // empty' 2>/dev/null)
        set eval_duration (echo "$response" | jq -r '.eval_duration // empty' 2>/dev/null)
        set prompt_eval_count (echo "$response" | jq -r '.prompt_eval_count // empty' 2>/dev/null)
        set prompt_eval_duration (echo "$response" | jq -r '.prompt_eval_duration // empty' 2>/dev/null)

        if test -n "$eval_count"; and test "$eval_count" != "null"; and test "$eval_count" != "0"
            # Generation tokens/s
            set ts (math -s2 "$eval_count / ($eval_duration / 1000000000)")

            # TTFT in ms
            set ttft (math -s1 "$prompt_eval_duration / 1000000")

            # Prompt evaluation t/s
            if test -n "$prompt_eval_count"; and test "$prompt_eval_count" != "null"; and test "$prompt_eval_count" != "0"
                set prompt_ts (math -s2 "$prompt_eval_count / ($prompt_eval_duration / 1000000000)")
            else
                set prompt_ts "N/A"
            end

            # VRAM (estimated model VRAM)
            set vram "$model_vram_mb"

            # Power - peak from samples
            if test -f "$power_samples_file"; and test -s "$power_samples_file"
                set power_max (sort -n "$power_samples_file" | tail -n 1)
                set power (math -s1 "$power_max / 1000000")
            else
                set power "N/A"
            end

            # Temperature
            if test -f "$temp_file_path"
                set temp_raw (cat "$temp_file_path")
                set temp (math -s0 "$temp_raw / 1000")
            else
                set temp "N/A"
            end

            # GPU clock - peak from samples
            if test -f "$clock_samples_file"; and test -s "$clock_samples_file"
                set gpu_clock (sort -n "$clock_samples_file" | tail -n 1)
            else
                set gpu_clock "N/A"
            end

            # VRAM actual usage (snapshot after inference)
            if test -f "$vram_used_file"
                set vram_used_raw (cat "$vram_used_file")
                set vram_used_mb (math -s0 "$vram_used_raw / 1048576")
            else
                set vram_used_mb "N/A"
            end

            # GTT - peak from samples (system RAM spillover)
            if test -f "$gtt_samples_file"; and test -s "$gtt_samples_file"
                set gtt_max (sort -n "$gtt_samples_file" | tail -n 1)
                set gtt_used_mb (math -s0 "$gtt_max / 1048576")
            else
                set gtt_used_mb "N/A"
            end

            # Efficiency: tokens per watt (t/s / W)
            if test "$power" != "N/A"; and test "$power" != "0"
                set efficiency (math -s3 "$ts / $power")
            else
                set efficiency "N/A"
            end

            # GPU utilization - average from samples
            if test -f "$gpu_busy_samples_file"; and test -s "$gpu_busy_samples_file"
                set gpu_busy_avg (awk '{s+=$1; n++} END {if(n>0) printf "%.0f", s/n}' "$gpu_busy_samples_file")
            else
                set gpu_busy_avg "N/A"
            end

            # Memory bus utilization - average from samples
            if test -f "$mem_busy_samples_file"; and test -s "$mem_busy_samples_file"
                set mem_busy_avg (awk '{s+=$1; n++} END {if(n>0) printf "%.0f", s/n}' "$mem_busy_samples_file")
            else
                set mem_busy_avg "N/A"
            end

            # Warmup label for output
            if test "$is_warmup" = "true"
                set warmup_label " WARMUP"
            else
                set warmup_label ""
            end

            # Output
            echo (date +"%H:%M:%S")" | $ts | $prompt_ts | $vram_used_mb MB | $power W | $temp°C | $gpu_clock MHz | GTT $gtt_used_mb MB | $efficiency | $gpu_busy_avg% | $mem_busy_avg%$warmup_label"

            # Save to CSV
            echo (date -Iseconds),"$ollama_version","$backend","$model","$model_size","$model_processor","$ts","$vram","$power","$temp","$ttft","$gpu_clock","$vram_used_mb","$gtt_used_mb","$efficiency","$baseline_vram_mb","$baseline_gtt_mb","$gpu_busy_avg","$mem_busy_avg","$is_warmup","$prompt_ts" >> "$csv_file"
        else
            echo (date +"%H:%M:%S")" | API Busy..."
        end

        # Clean up temp files
        rm -f "$power_samples_file" "$clock_samples_file" "$gtt_samples_file" "$gpu_busy_samples_file" "$mem_busy_samples_file"

        sleep 1
    end
end

ollama_bench
