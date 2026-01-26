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

    # Modell laden falls nicht aktiv
    echo "Lade Modell $model..."
    curl -s -X POST http://localhost:11434/api/generate \
        -d "{\"model\": \"$model\", \"prompt\": \"hi\", \"stream\": false}" >/dev/null

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

    # CSV-Header schreiben falls neu
    if not test -f "$csv_file"
        echo "timestamp,ollama_version,backend,model,model_size,gpu_offload,tokens_per_sec,vram_mb,power_w,temp_c,ttft_ms" > "$csv_file"
    end

    echo "==============================================="
    echo "  Ollama Benchmark"
    echo "==============================================="
    echo "Ollama:  $ollama_version"
    echo "Backend: $backend"
    echo "Modell:  $model"
    echo "Größe:   $model_size"
    echo "Offload: $model_processor"
    echo "CSV:     $csv_file"
    echo "-----------------------------------------------"
    echo "Zeit     | t/s   | VRAM    | Power | Temp"
    echo "-----------------------------------------------"

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

        # Power-Sampler im Hintergrund starten (alle 100ms)
        if test -f "$power_file"
            fish -c "
                while true
                    cat '$power_file' >> '$power_samples_file'
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

            # Ausgabe
            echo (date +"%H:%M:%S")" | $ts | $vram MB | $power W | $temp°C"

            # CSV speichern
            echo (date -Iseconds),"$ollama_version","$backend","$model","$model_size","$model_processor","$ts","$vram","$power","$temp","$ttft" >> "$csv_file"
        else
            echo (date +"%H:%M:%S")" | API Busy..."
        end

        # Temp-Datei aufräumen
        rm -f "$power_samples_file"

        sleep 1
    end
end

ollama_bench
