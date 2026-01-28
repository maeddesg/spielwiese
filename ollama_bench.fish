#!/usr/bin/fish

function ollama_bench
    set model "qwen3-coder:30b"
    set card_path "/sys/class/drm/card1/device"
    set context_sizes 2048 4096 8192 16384 32768
    set runs_per_ctx 6

    # Prompt catalog: IDs, names, and texts (parallel lists, indexed 1-9)
    set prompt_ids \
        code_short    code_medium    code_long \
        prose_short   prose_medium   prose_long \
        reason_short  reason_medium  reason_long
    set prompt_names \
        "Prime Check" "LRU Cache"    "REST API" \
        "Mutex Explanation" "TCP vs UDP" "GPU Architecture" \
        "Complexity"  "Debug Code"   "System Design"
    set prompt_texts \
        "Write a Python function that checks if a number is prime." \
        "Write a C++ class implementing a thread-safe LRU cache with get, put, and delete operations. Include proper mutex locking and comments." \
        "Write a REST API in Go with endpoints for user authentication (register, login, logout), JWT token handling, password hashing with bcrypt, and rate limiting middleware. Include error handling, input validation, and code comments." \
        "Explain what a mutex is in one paragraph." \
        "Compare and contrast TCP and UDP protocols. Cover reliability, speed, use cases, and header differences." \
        "Write a detailed technical blog post about the evolution of GPU architectures from CUDA to modern compute shaders, covering parallel processing concepts, memory hierarchies, and real-world applications in machine learning and graphics." \
        "What is the time complexity of binary search and why?" \
        "Debug this code and explain the issue: for(int i=0; i<=arr.length; i++) sum += arr[i];" \
        "Design a distributed message queue system. Describe the architecture, how you would handle failover, message persistence, ordering guarantees, and horizontal scaling. Compare tradeoffs between at-least-once and exactly-once delivery."

    # Interactive prompt selection menu
    while true
        echo "╔══════════════════════════════════════╗"
        echo "║      Ollama Benchmark - Prompt       ║"
        echo "╚══════════════════════════════════════╝"
        echo ""
        echo "Choose a category:"
        echo ""
        echo "  1) Code Generation"
        echo "  2) Prose / Text"
        echo "  3) Reasoning / Analysis"
        echo "  4) Custom Prompt"
        echo "  0) Exit"
        echo ""
        read -P "Selection: " category_choice

        switch $category_choice
            case 0
                echo "Exiting."
                return 0
            case 1
                set cat_label "Code Generation"
                set cat_offset 0
            case 2
                set cat_label "Prose / Text"
                set cat_offset 3
            case 3
                set cat_label "Reasoning / Analysis"
                set cat_offset 6
            case 4
                read -P "Enter your custom prompt: " custom_input
                if test -z "$custom_input"
                    echo "Empty prompt, try again."
                    echo ""
                    continue
                end
                set prompt_id "custom"
                set prompt_name "Custom"
                set prompt_text "$custom_input"
                break
            case '*'
                echo "Invalid selection, try again."
                echo ""
                continue
        end

        # Level 2: prompt length sub-menu
        set idx1 (math $cat_offset + 1)
        set idx2 (math $cat_offset + 2)
        set idx3 (math $cat_offset + 3)
        echo ""
        echo "╔══════════════════════════════════════╗"
        echo "║  $cat_label Prompts"
        echo "╚══════════════════════════════════════╝"
        echo ""
        echo "Choose a prompt:"
        echo ""
        echo "  1) Short  - $prompt_names[$idx1]"
        echo "  2) Medium - $prompt_names[$idx2]"
        echo "  3) Long   - $prompt_names[$idx3]"
        echo "  0) Back"
        echo ""
        read -P "Selection: " length_choice

        switch $length_choice
            case 0
                echo ""
                continue
            case 1
                set prompt_id $prompt_ids[$idx1]
                set prompt_name $prompt_names[$idx1]
                set prompt_text $prompt_texts[$idx1]
                break
            case 2
                set prompt_id $prompt_ids[$idx2]
                set prompt_name $prompt_names[$idx2]
                set prompt_text $prompt_texts[$idx2]
                break
            case 3
                set prompt_id $prompt_ids[$idx3]
                set prompt_name $prompt_names[$idx3]
                set prompt_text $prompt_texts[$idx3]
                break
            case '*'
                echo "Invalid selection, try again."
                echo ""
                continue
        end
    end

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

    set json_file "benchmark_$backend.json"

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

    # Create JSON file if new (empty file, JSONL format)
    if not test -f "$json_file"
        touch "$json_file"
    end

    # Power file
    set hwmon_files $card_path/hwmon/hwmon*/power1_average
    set power_file "$hwmon_files[1]"

    # Temperature file
    set temp_files $card_path/hwmon/hwmon*/temp1_input
    set temp_file_path "$temp_files[1]"

    echo "==============================================="
    echo "  Ollama Benchmark"
    echo "==============================================="
    echo "Ollama:   $ollama_version"
    echo "Backend:  $backend"
    echo "Model:    $model"
    echo "Contexts: $context_sizes"
    echo "Runs:     $runs_per_ctx per context size (1 warmup + "(math $runs_per_ctx - 1)" measured)"
    echo "Prompt:   $prompt_name ($prompt_id)"
    echo "JSON:     $json_file"
    echo "==============================================="

    # Clean exit on Ctrl+C
    function _cleanup --on-signal INT --on-signal TERM
        # Stop background sampler if active
        if set -q _power_sampler_pid
            kill $_power_sampler_pid 2>/dev/null
        end
        echo ""
        echo "Benchmark interrupted."
        exit 0
    end

    for num_ctx in $context_sizes
        # Stop model before each context size for clean KV cache
        echo ""
        echo "--- Stopping model for context size $num_ctx ---"
        ollama stop "$model" 2>/dev/null
        sleep 2

        # Reload model with this num_ctx
        echo "Loading model $model with num_ctx=$num_ctx..."
        curl -s -X POST http://localhost:11434/api/generate \
            -d "{\"model\": \"$model\", \"prompt\": \"hi\", \"stream\": false, \"options\": {\"num_ctx\": $num_ctx}}" >/dev/null

        # Measure VRAM/GTT after loading with this context size
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

        # Calculate delta (actual model footprint for this context size)
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

        echo "-------------------------------------------------------------------------------------------------------------------"
        echo "  num_ctx=$num_ctx | Size: $model_size | Offload: $model_processor"
        echo "  VRAM: $vram_total_mb MB total | Baseline: $baseline_vram_mb MB | Model: +$delta_vram_mb MB | Loaded: $loaded_vram_mb MB"
        echo "  GTT:  $gtt_total_mb MB total | Baseline: $baseline_gtt_mb MB | Model: +$delta_gtt_mb MB | Loaded: $loaded_gtt_mb MB"
        echo "-------------------------------------------------------------------------------------------------------------------"
        echo "Time     | Gen t/s | Prompt t/s | VRAM    | Power | Temp  | Clock   | GTT     | t/W   | GPU%  | MEM%  |"
        echo "-------------------------------------------------------------------------------------------------------------------"

        for run in (seq $runs_per_ctx)
            if test "$run" -eq 1
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

            # Run inference with num_ctx
            set prompt_escaped (echo "$prompt_text" | string replace -a '"' '\\"')
            set response (curl -s -X POST http://localhost:11434/api/generate \
                -d "{\"model\": \"$model\", \"prompt\": \"$prompt_escaped\", \"stream\": false, \"options\": {\"num_ctx\": $num_ctx}}")

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

                # Save to JSON (JSONL format)
                jq -n -c \
                    --arg timestamp (date -Iseconds) \
                    --arg ollama_version "$ollama_version" \
                    --arg backend "$backend" \
                    --arg model "$model" \
                    --arg model_size "$model_size" \
                    --arg gpu_offload "$model_processor" \
                    --argjson num_ctx "$num_ctx" \
                    --arg tokens_per_sec "$ts" \
                    --arg vram_mb "$vram" \
                    --arg power_w "$power" \
                    --arg temp_c "$temp" \
                    --arg ttft_ms "$ttft" \
                    --arg gpu_clock_mhz "$gpu_clock" \
                    --arg vram_used_mb "$vram_used_mb" \
                    --arg gtt_used_mb "$gtt_used_mb" \
                    --arg efficiency_tpw "$efficiency" \
                    --arg vram_baseline_mb "$baseline_vram_mb" \
                    --arg gtt_baseline_mb "$baseline_gtt_mb" \
                    --arg gpu_busy_pct "$gpu_busy_avg" \
                    --arg mem_busy_pct "$mem_busy_avg" \
                    --arg warmup "$is_warmup" \
                    --arg prompt_tokens_per_sec "$prompt_ts" \
                    --arg prompt_id "$prompt_id" \
                    '{
                        timestamp: $timestamp,
                        ollama_version: $ollama_version,
                        backend: $backend,
                        model: $model,
                        model_size: $model_size,
                        gpu_offload: $gpu_offload,
                        num_ctx: $num_ctx,
                        tokens_per_sec: ($tokens_per_sec | tonumber? // $tokens_per_sec),
                        vram_mb: ($vram_mb | tonumber? // $vram_mb),
                        power_w: ($power_w | tonumber? // $power_w),
                        temp_c: ($temp_c | tonumber? // $temp_c),
                        ttft_ms: ($ttft_ms | tonumber? // $ttft_ms),
                        gpu_clock_mhz: ($gpu_clock_mhz | tonumber? // $gpu_clock_mhz),
                        vram_used_mb: ($vram_used_mb | tonumber? // $vram_used_mb),
                        gtt_used_mb: ($gtt_used_mb | tonumber? // $gtt_used_mb),
                        efficiency_tpw: ($efficiency_tpw | tonumber? // $efficiency_tpw),
                        vram_baseline_mb: ($vram_baseline_mb | tonumber? // $vram_baseline_mb),
                        gtt_baseline_mb: ($gtt_baseline_mb | tonumber? // $gtt_baseline_mb),
                        gpu_busy_pct: ($gpu_busy_pct | tonumber? // $gpu_busy_pct),
                        mem_busy_pct: ($mem_busy_pct | tonumber? // $mem_busy_pct),
                        warmup: ($warmup == "true"),
                        prompt_tokens_per_sec: ($prompt_tokens_per_sec | tonumber? // $prompt_tokens_per_sec),
                        prompt_id: $prompt_id
                    }' >> "$json_file"
            else
                echo (date +"%H:%M:%S")" | API Busy..."
            end

            # Clean up temp files
            rm -f "$power_samples_file" "$clock_samples_file" "$gtt_samples_file" "$gpu_busy_samples_file" "$mem_busy_samples_file"

            sleep 1
        end
    end

    echo ""
    echo "==============================================="
    echo "  Benchmark complete."
    echo "==============================================="
end

ollama_bench
