#!/usr/bin/fish

function ollama_bench
    set model "qwen3-coder:30b"
    set card_path "/sys/class/drm/card1/device"

    # Abhängigkeiten prüfen
    if not command -q jq
        echo "Fehler: jq ist nicht installiert"
        return 1
    end

    if not command -q curl
        echo "Fehler: curl ist nicht installiert"
        return 1
    end

    # Prüfen ob Ollama läuft
    if not curl -s http://localhost:11434/api/tags >/dev/null 2>&1
        echo "Fehler: Ollama läuft nicht (Port 11434)"
        return 1
    end

    # Backend automatisch erkennen
    if pacman -Qq ollama-vulkan &>/dev/null
        set backend "vulkan"
    else if pacman -Qq ollama-rocm &>/dev/null
        set backend "rocm"
    else
        set backend "cpu"
    end

    # Ollama Version
    set ollama_version (ollama --version | string replace "ollama version is " "")

    set csv_file "benchmark_$backend.csv"

    # Speicher-Dateien ermitteln (früh, für Baseline)
    set vram_used_file "$card_path/mem_info_vram_used"
    set gtt_used_file "$card_path/mem_info_gtt_used"

    # Modell stoppen für saubere VRAM-Ausgangslage
    echo "Stoppe Modell $model für saubere Baseline..."
    ollama stop "$model" 2>/dev/null
    sleep 2

    # VRAM/GTT Baseline messen (ohne Modell = Firefox, Compositor, etc.)
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

    # Modell neu laden
    echo "Lade Modell $model..."
    curl -s -X POST http://localhost:11434/api/generate \
        -d "{\"model\": \"$model\", \"prompt\": \"hi\", \"stream\": false}" >/dev/null

    # VRAM/GTT nach Laden messen
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

    # Delta berechnen (was das Modell tatsächlich belegt)
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

    # Modell-Info holen (awk für korrekte Spalten-Trennung)
    set model_info (ollama ps 2>/dev/null | grep "$model")
    if test -n "$model_info"
        set model_size_num (echo "$model_info" | awk '{print $3}')
        set model_size_unit (echo "$model_info" | awk '{print $4}')
        set model_size "$model_size_num"_"$model_size_unit"
        set processor_raw (echo "$model_info" | awk '{print $5}')
        # Prozente aufteilen (z.B. "23%/77%" -> "23% (RAM) / 77% (VRAM)")
        set cpu_pct (echo "$processor_raw" | string split "/" | head -n 1)
        set gpu_pct (echo "$processor_raw" | string split "/" | tail -n 1)
        set model_processor "$cpu_pct (RAM) / $gpu_pct (VRAM)"
        # GPU-Prozent als Zahl für VRAM-Berechnung (z.B. "77%" -> 77)
        set gpu_pct_num (echo "$gpu_pct" | string replace "%" "")
        # Modellgröße in MB umrechnen
        if test "$model_size_unit" = "GB"
            set model_size_mb (math "$model_size_num * 1024")
        else
            set model_size_mb "$model_size_num"
        end
        # VRAM des Modells berechnen (Modellgröße × GPU%)
        set model_vram_mb (math -s0 "$model_size_mb * $gpu_pct_num / 100")
    else
        set model_size "N/A"
        set model_processor "N/A"
        set model_vram_mb "N/A"
    end

    # GPU-Clock-Datei ermitteln
    set sclk_file "$card_path/pp_dpm_sclk"

    # GPU-Auslastungs-Dateien
    set gpu_busy_file "$card_path/gpu_busy_percent"
    set mem_busy_file "$card_path/mem_busy_percent"

    # Speicher-Dateien ermitteln (Total)
    set vram_total_file "$card_path/mem_info_vram_total"
    set gtt_total_file "$card_path/mem_info_gtt_total"

    # VRAM/GTT Total einmalig lesen
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

    # CSV-Header schreiben falls neu
    if not test -f "$csv_file"
        echo "timestamp,ollama_version,backend,model,model_size,gpu_offload,tokens_per_sec,vram_mb,power_w,temp_c,ttft_ms,gpu_clock_mhz,vram_used_mb,gtt_used_mb,efficiency_tpj,vram_baseline_mb,gtt_baseline_mb,gpu_busy_pct,mem_busy_pct" > "$csv_file"
    end

    echo "==============================================="
    echo "  Ollama Benchmark"
    echo "==============================================="
    echo "Ollama:  $ollama_version"
    echo "Backend: $backend"
    echo "Modell:  $model"
    echo "Größe:   $model_size"
    echo "Offload: $model_processor"
    echo "VRAM:    $vram_total_mb MB total | Baseline: $baseline_vram_mb MB | Modell: +$delta_vram_mb MB | Geladen: $loaded_vram_mb MB"
    echo "GTT:     $gtt_total_mb MB total | Baseline: $baseline_gtt_mb MB | Modell: +$delta_gtt_mb MB | Geladen: $loaded_gtt_mb MB"
    echo "CSV:     $csv_file"
    echo "-----------------------------------------------------------------------------------------------"
    echo "Zeit     | t/s   | VRAM    | Power | Temp  | Clock   | GTT     | t/J   | GPU%  | MEM%"
    echo "-----------------------------------------------------------------------------------------------"

    # Power-Datei ermitteln
    set hwmon_files $card_path/hwmon/hwmon*/power1_average
    set power_file "$hwmon_files[1]"

    # Temp-Datei ermitteln
    set temp_files $card_path/hwmon/hwmon*/temp1_input
    set temp_file_path "$temp_files[1]"

    # Sauberer Exit bei Ctrl+C
    function _cleanup --on-signal INT --on-signal TERM
        # Hintergrund-Sampler beenden falls aktiv
        if set -q _power_sampler_pid
            kill $_power_sampler_pid 2>/dev/null
        end
        echo ""
        echo "Benchmark beendet."
        exit 0
    end

    while true
        # Temp-Datei für Power-Sampling
        set power_samples_file (mktemp)

        # Sample-Dateien
        set clock_samples_file (mktemp)
        set gtt_samples_file (mktemp)
        set gpu_busy_samples_file (mktemp)
        set mem_busy_samples_file (mktemp)

        # Hintergrund-Sampler starten (alle 100ms)
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

        # Inference ausführen
        set response (curl -s -X POST http://localhost:11434/api/generate \
            -d "{\"model\": \"$model\", \"prompt\": \"Schreibe eine performante Funktion in C++, die einen Binärbaum invertiert.\", \"stream\": false}")

        # Power-Sampler stoppen
        if set -q _power_sampler_pid
            kill $_power_sampler_pid 2>/dev/null
            set -e _power_sampler_pid
        end

        set eval_count (echo "$response" | jq -r '.eval_count // empty' 2>/dev/null)
        set eval_duration (echo "$response" | jq -r '.eval_duration // empty' 2>/dev/null)
        set prompt_eval_duration (echo "$response" | jq -r '.prompt_eval_duration // empty' 2>/dev/null)

        if test -n "$eval_count"; and test "$eval_count" != "null"; and test "$eval_count" != "0"
            # Tokens/s
            set ts (math -s2 "$eval_count / ($eval_duration / 1000000000)")

            # TTFT in ms
            set ttft (math -s1 "$prompt_eval_duration / 1000000")

            # VRAM (berechneter Modell-VRAM)
            set vram "$model_vram_mb"

            # Power - Maximum aus Samples nehmen
            if test -f "$power_samples_file"; and test -s "$power_samples_file"
                set power_max (sort -n "$power_samples_file" | tail -n 1)
                set power (math -s1 "$power_max / 1000000")
            else
                set power "N/A"
            end

            # Temperatur
            if test -f "$temp_file_path"
                set temp_raw (cat "$temp_file_path")
                set temp (math -s0 "$temp_raw / 1000")
            else
                set temp "N/A"
            end

            # GPU-Clock - Maximum aus Samples
            if test -f "$clock_samples_file"; and test -s "$clock_samples_file"
                set gpu_clock (sort -n "$clock_samples_file" | tail -n 1)
            else
                set gpu_clock "N/A"
            end

            # VRAM tatsächlich belegt (Snapshot nach Inference)
            if test -f "$vram_used_file"
                set vram_used_raw (cat "$vram_used_file")
                set vram_used_mb (math -s0 "$vram_used_raw / 1048576")
            else
                set vram_used_mb "N/A"
            end

            # GTT - Maximum aus Samples (Spillover in System-RAM)
            if test -f "$gtt_samples_file"; and test -s "$gtt_samples_file"
                set gtt_max (sort -n "$gtt_samples_file" | tail -n 1)
                set gtt_used_mb (math -s0 "$gtt_max / 1048576")
            else
                set gtt_used_mb "N/A"
            end

            # Effizienz: Tokens pro Joule (t/s / W)
            if test "$power" != "N/A"; and test "$power" != "0"
                set efficiency (math -s3 "$ts / $power")
            else
                set efficiency "N/A"
            end

            # GPU-Auslastung - Durchschnitt aus Samples
            if test -f "$gpu_busy_samples_file"; and test -s "$gpu_busy_samples_file"
                set gpu_busy_avg (awk '{s+=$1; n++} END {if(n>0) printf "%.0f", s/n}' "$gpu_busy_samples_file")
            else
                set gpu_busy_avg "N/A"
            end

            # Speicherbus-Auslastung - Durchschnitt aus Samples
            if test -f "$mem_busy_samples_file"; and test -s "$mem_busy_samples_file"
                set mem_busy_avg (awk '{s+=$1; n++} END {if(n>0) printf "%.0f", s/n}' "$mem_busy_samples_file")
            else
                set mem_busy_avg "N/A"
            end

            # Ausgabe
            echo (date +"%H:%M:%S")" | $ts | $vram_used_mb MB | $power W | $temp°C | $gpu_clock MHz | GTT $gtt_used_mb MB | $efficiency | $gpu_busy_avg% | $mem_busy_avg%"

            # CSV speichern
            echo (date -Iseconds),"$ollama_version","$backend","$model","$model_size","$model_processor","$ts","$vram","$power","$temp","$ttft","$gpu_clock","$vram_used_mb","$gtt_used_mb","$efficiency","$baseline_vram_mb","$baseline_gtt_mb","$gpu_busy_avg","$mem_busy_avg" >> "$csv_file"
        else
            echo (date +"%H:%M:%S")" | API Busy..."
        end

        # Temp-Dateien aufräumen
        rm -f "$power_samples_file" "$clock_samples_file" "$gtt_samples_file" "$gpu_busy_samples_file" "$mem_busy_samples_file"

        sleep 1
    end
end

ollama_bench
