# ollama_bench.ps1 - Ollama Benchmark for Windows
# PowerShell port of ollama_bench.fish
# Requires: Ollama running on localhost:11434

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Ollama-Bench {
    $model = "qwen3-coder:30b"
    $contextSizes = @(2048, 4096, 8192, 16384, 32768)
    $runsPerCtx = 6

    # Prompt catalog
    $prompts = @(
        @{ id = "code_short";    name = "Prime Check";       text = "Write a Python function that checks if a number is prime." }
        @{ id = "code_medium";   name = "LRU Cache";         text = "Write a C++ class implementing a thread-safe LRU cache with get, put, and delete operations. Include proper mutex locking and comments." }
        @{ id = "code_long";     name = "REST API";          text = "Write a REST API in Go with endpoints for user authentication (register, login, logout), JWT token handling, password hashing with bcrypt, and rate limiting middleware. Include error handling, input validation, and code comments." }
        @{ id = "prose_short";   name = "Mutex Explanation";  text = "Explain what a mutex is in one paragraph." }
        @{ id = "prose_medium";  name = "TCP vs UDP";        text = "Compare and contrast TCP and UDP protocols. Cover reliability, speed, use cases, and header differences." }
        @{ id = "prose_long";    name = "GPU Architecture";  text = "Write a detailed technical blog post about the evolution of GPU architectures from CUDA to modern compute shaders, covering parallel processing concepts, memory hierarchies, and real-world applications in machine learning and graphics." }
        @{ id = "reason_short";  name = "Complexity";        text = "What is the time complexity of binary search and why?" }
        @{ id = "reason_medium"; name = "Debug Code";        text = "Debug this code and explain the issue: for(int i=0; i<=arr.length; i++) sum += arr[i];" }
        @{ id = "reason_long";   name = "System Design";     text = "Design a distributed message queue system. Describe the architecture, how you would handle failover, message persistence, ordering guarantees, and horizontal scaling. Compare tradeoffs between at-least-once and exactly-once delivery." }
    )

    # --- Interactive prompt selection menu ---
    $promptId = $null
    $promptName = $null
    $promptText = $null
    $menuDone = $false

    while (-not $menuDone) {
        Write-Host ""
        Write-Host ([char]0x2554 + ([string][char]0x2550) * 38 + [char]0x2557)
        Write-Host ([char]0x2551 + "      Ollama Benchmark - Prompt       " + [char]0x2551)
        Write-Host ([char]0x255A + ([string][char]0x2550) * 38 + [char]0x255D)
        Write-Host ""
        Write-Host "Choose a category:"
        Write-Host ""
        Write-Host "  1) Code Generation"
        Write-Host "  2) Prose / Text"
        Write-Host "  3) Reasoning / Analysis"
        Write-Host "  4) Custom Prompt"
        Write-Host "  0) Exit"
        Write-Host ""
        $categoryChoice = Read-Host "Selection"

        if ($categoryChoice -eq "0") {
            Write-Host "Exiting."
            return
        }
        elseif ($categoryChoice -eq "1") { $catLabel = "Code Generation"; $catOffset = 0 }
        elseif ($categoryChoice -eq "2") { $catLabel = "Prose / Text";    $catOffset = 3 }
        elseif ($categoryChoice -eq "3") { $catLabel = "Reasoning / Analysis"; $catOffset = 6 }
        elseif ($categoryChoice -eq "4") {
            $customInput = Read-Host "Enter your custom prompt"
            if ([string]::IsNullOrWhiteSpace($customInput)) {
                Write-Host "Empty prompt, try again."
                continue
            }
            $promptId   = "custom"
            $promptName = "Custom"
            $promptText = $customInput
            $menuDone   = $true
            continue
        }
        else {
            Write-Host "Invalid selection, try again."
            continue
        }

        # Level 2: prompt length sub-menu
        $idx1 = $catOffset
        $idx2 = $catOffset + 1
        $idx3 = $catOffset + 2
        Write-Host ""
        Write-Host ([char]0x2554 + ([string][char]0x2550) * 38 + [char]0x2557)
        Write-Host ([char]0x2551 + "  $catLabel Prompts".PadRight(38) + [char]0x2551)
        Write-Host ([char]0x255A + ([string][char]0x2550) * 38 + [char]0x255D)
        Write-Host ""
        Write-Host "Choose a prompt:"
        Write-Host ""
        Write-Host "  1) Short  - $($prompts[$idx1].name)"
        Write-Host "  2) Medium - $($prompts[$idx2].name)"
        Write-Host "  3) Long   - $($prompts[$idx3].name)"
        Write-Host "  0) Back"
        Write-Host ""
        $lengthChoice = Read-Host "Selection"

        if ($lengthChoice -eq "0") {
            continue
        }
        elseif ($lengthChoice -eq "1") {
            $promptId   = $prompts[$idx1].id
            $promptName = $prompts[$idx1].name
            $promptText = $prompts[$idx1].text
            $menuDone   = $true
        }
        elseif ($lengthChoice -eq "2") {
            $promptId   = $prompts[$idx2].id
            $promptName = $prompts[$idx2].name
            $promptText = $prompts[$idx2].text
            $menuDone   = $true
        }
        elseif ($lengthChoice -eq "3") {
            $promptId   = $prompts[$idx3].id
            $promptName = $prompts[$idx3].name
            $promptText = $prompts[$idx3].text
            $menuDone   = $true
        }
        else {
            Write-Host "Invalid selection, try again."
            continue
        }
    }

    # --- Check if Ollama is running ---
    try {
        $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -ErrorAction Stop
    } catch {
        Write-Host "Error: Ollama is not running (port 11434)"
        return
    }

    # --- Detect backend ---
    $backend = "windows"
    $gpuName = "Unknown"
    try {
        $gpuAdapter = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -notmatch "Microsoft Basic|Remote Desktop" } |
            Select-Object -First 1
        if ($gpuAdapter) {
            $gpuName = $gpuAdapter.Name
            if ($gpuName -match "NVIDIA")     { $backend = "windows-cuda" }
            elseif ($gpuName -match "AMD|Radeon") { $backend = "windows-amd" }
            elseif ($gpuName -match "Intel")  { $backend = "windows-intel" }
        }
    } catch { }

    # --- Ollama version ---
    $ollamaVersion = "unknown"
    try {
        $ollamaVersionRaw = & ollama --version 2>&1 | Out-String
        $ollamaVersion = ($ollamaVersionRaw -replace "ollama version is ", "").Trim()
    } catch { }

    $jsonFile = "benchmark_$backend.json"

    # --- GPU Monitoring Setup ---
    # nvidia-smi (NVIDIA GPUs)
    $hasNvidiaSmi = $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)

    # Windows Performance Counters (AMD/Intel)
    $hasGpuCounters = $false
    try {
        $null = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop -MaxSamples 1
        $hasGpuCounters = $true
    } catch { }

    # --- VRAM total from registry (bypasses WMI 4GB UInt32 cap) ---
    $vramTotalMb = "N/A"
    try {
        $regPaths = Get-ItemProperty "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*" `
            -Name "HardwareInformation.qwMemorySize" -ErrorAction SilentlyContinue
        if ($regPaths) {
            $vramBytes = ($regPaths | Select-Object -First 1)."HardwareInformation.qwMemorySize"
            if ($vramBytes -and $vramBytes -gt 0) {
                $vramTotalMb = [math]::Round([uint64]$vramBytes / 1MB, 0)
            }
        }
    } catch { }
    # Fallback to WMI if registry failed
    if ($vramTotalMb -eq "N/A") {
        try {
            $adapter = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                Where-Object { $_.Name -notmatch "Microsoft Basic|Remote Desktop" } |
                Select-Object -First 1
            if ($adapter.AdapterRAM -and $adapter.AdapterRAM -gt 0) {
                $vramTotalMb = [math]::Round([uint64]$adapter.AdapterRAM / 1MB, 0)
            }
        } catch { }
    }

    # --- GPU Metrics Snapshot Function ---
    function Get-GpuMetrics {
        $metrics = @{
            vram_used_mb  = "N/A"
            shared_used_mb = "N/A"
            gpu_busy_pct  = "N/A"
            temp_c        = "N/A"
            power_w       = "N/A"
            gpu_clock_mhz = "N/A"
        }

        if ($hasNvidiaSmi) {
            try {
                $smiOutput = & nvidia-smi --query-gpu=memory.used,utilization.gpu,utilization.memory,temperature.gpu,power.draw,clocks.gr '--format=csv,noheader,nounits' 2>$null
                if ($smiOutput) {
                    $parts = $smiOutput.Split(",") | ForEach-Object { $_.Trim() }
                    if ($parts.Count -ge 6) {
                        $metrics.vram_used_mb  = [int]$parts[0]
                        $metrics.gpu_busy_pct  = [int]$parts[1]
                        $metrics.temp_c        = [int]$parts[3]
                        $metrics.power_w       = [math]::Round([double]$parts[4], 1)
                        $metrics.gpu_clock_mhz = [int]$parts[5]
                    }
                }
            } catch { }
            return $metrics
        }

        if ($hasGpuCounters) {
            try {
                $gpuSamples = (Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                $gpuUtil = ($gpuSamples | Measure-Object -Property CookedValue -Sum).Sum
                $metrics.gpu_busy_pct = [math]::Round($gpuUtil, 0)
            } catch { }
            try {
                $memSamples = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                $dedicatedBytes = ($memSamples | Measure-Object -Property CookedValue -Sum).Sum
                $metrics.vram_used_mb = [math]::Round($dedicatedBytes / 1MB, 0)
            } catch { }
            try {
                $sharedSamples = (Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                $sharedBytes = ($sharedSamples | Measure-Object -Property CookedValue -Sum).Sum
                $metrics.shared_used_mb = [math]::Round($sharedBytes / 1MB, 0)
            } catch { }
        }

        return $metrics
    }

    # --- Stop model for clean baseline ---
    Write-Host "Stopping model $model for clean baseline..."
    $null = & ollama stop $model 2>&1
    Start-Sleep -Seconds 2

    # Baseline GPU metrics
    $baselineMetrics = Get-GpuMetrics
    $baselineVramMb  = $baselineMetrics.vram_used_mb
    $baselineSharedMb = $baselineMetrics.shared_used_mb

    # Create JSON file if it doesn't exist
    if (-not (Test-Path $jsonFile)) {
        $null = New-Item -Path $jsonFile -ItemType File -Force
    }

    Write-Host "==============================================="
    Write-Host "  Ollama Benchmark (Windows)"
    Write-Host "==============================================="
    Write-Host "Ollama:   $ollamaVersion"
    Write-Host "Backend:  $backend"
    Write-Host "GPU:      $gpuName"
    Write-Host "Model:    $model"
    Write-Host "VRAM:     $vramTotalMb MB"
    Write-Host "Contexts: $($contextSizes -join ', ')"
    Write-Host "Runs:     $runsPerCtx per context size (1 warmup + $($runsPerCtx - 1) measured)"
    Write-Host "Prompt:   $promptName ($promptId)"
    Write-Host "JSON:     $jsonFile"
    if ($hasNvidiaSmi)       { Write-Host "GPU Mon:  nvidia-smi (full metrics)" }
    elseif ($hasGpuCounters) { Write-Host "GPU Mon:  Windows Performance Counters (VRAM + GPU%)" }
    else                     { Write-Host "GPU Mon:  Limited (no nvidia-smi or perf counters)" }
    Write-Host "==============================================="

    foreach ($numCtx in $contextSizes) {
        # Stop model before each context size for clean KV cache
        Write-Host ""
        Write-Host "--- Stopping model for context size $numCtx ---"
        $null = & ollama stop $model 2>&1
        Start-Sleep -Seconds 2

        # Reload model with this num_ctx
        Write-Host "Loading model $model with num_ctx=$numCtx..."
        $loadBody = @{
            model   = $model
            prompt  = "hi"
            stream  = $false
            options = @{ num_ctx = $numCtx }
        } | ConvertTo-Json -Depth 3
        try {
            $null = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $loadBody -ContentType "application/json" -TimeoutSec 300 -ErrorAction Stop
        } catch {
            Write-Host "Warning: Failed to pre-load model: $_"
        }

        # Measure VRAM after loading
        $loadedMetrics = Get-GpuMetrics
        $loadedVramMb  = $loadedMetrics.vram_used_mb

        # Calculate delta
        if ($baselineVramMb -ne "N/A" -and $loadedVramMb -ne "N/A") {
            $deltaVramMb = [int]$loadedVramMb - [int]$baselineVramMb
        } else {
            $deltaVramMb = "N/A"
        }

        # Get model info from ollama ps
        $modelSize      = "N/A"
        $modelProcessor = "N/A"
        $modelVramMb    = "N/A"
        try {
            $psOutput = & ollama ps 2>&1 | Out-String
            $psLines = $psOutput -split "`n" | Where-Object { $_ -match [regex]::Escape($model) }
            if ($psLines) {
                $modelLine = ($psLines | Select-Object -First 1).Trim()
                # Format A: "18 GB  23%/77%"  (split offload)
                if ($modelLine -match '(\d+\.?\d*)\s+(GB|MB)\s+(\d+%)\s*/\s*(\d+%)') {
                    $sizeNum    = [double]$Matches[1]
                    $sizeUnit   = $Matches[2]
                    $cpuPct     = $Matches[3]
                    $gpuPct     = $Matches[4]
                    $modelSize  = "${sizeNum}_${sizeUnit}"
                    $modelProcessor = "$cpuPct (RAM) / $gpuPct (VRAM)"
                    $gpuPctNum  = [int]($gpuPct -replace "%", "")
                    $modelSizeMb = if ($sizeUnit -eq "GB") { $sizeNum * 1024 } else { $sizeNum }
                    $modelVramMb = [math]::Round($modelSizeMb * $gpuPctNum / 100, 0)
                }
                # Format B: "18 GB  100% GPU" (full GPU offload)
                elseif ($modelLine -match '(\d+\.?\d*)\s+(GB|MB)\s+(\d+)%\s*GPU') {
                    $sizeNum    = [double]$Matches[1]
                    $sizeUnit   = $Matches[2]
                    $gpuPctNum  = [int]$Matches[3]
                    $modelSize  = "${sizeNum}_${sizeUnit}"
                    $cpuPctNum  = 100 - $gpuPctNum
                    $modelProcessor = "${cpuPctNum}% (RAM) / ${gpuPctNum}% (VRAM)"
                    $modelSizeMb = if ($sizeUnit -eq "GB") { $sizeNum * 1024 } else { $sizeNum }
                    $modelVramMb = [math]::Round($modelSizeMb * $gpuPctNum / 100, 0)
                }
            }
        } catch { }

        Write-Host "-------------------------------------------------------------------------------------------------------------------"
        Write-Host "  num_ctx=$numCtx | Size: $modelSize | Offload: $modelProcessor"
        Write-Host "  VRAM: $vramTotalMb MB total | Baseline: $baselineVramMb MB | Model: +$deltaVramMb MB | Loaded: $loadedVramMb MB"
        Write-Host "-------------------------------------------------------------------------------------------------------------------"
        Write-Host "Time     | Gen t/s | Prompt t/s | VRAM    | Power | Temp  | Clock   | Shared  | t/W   | GPU%  |"
        Write-Host "-------------------------------------------------------------------------------------------------------------------"

        for ($run = 1; $run -le $runsPerCtx; $run++) {
            $isWarmup = ($run -eq 1)

            # --- Run inference ---
            $body = @{
                model   = $model
                prompt  = $promptText
                stream  = $false
                options = @{ num_ctx = $numCtx }
            } | ConvertTo-Json -Depth 3

            $response = $null
            try {
                $response = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 600 -ErrorAction Stop
            } catch {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') | API Error: $_"
                Start-Sleep -Seconds 1
                continue
            }

            # Take a snapshot of GPU metrics right after inference
            $snap = Get-GpuMetrics

            if ($null -ne $response -and $null -ne $response.eval_count -and $response.eval_count -gt 0) {
                # Generation tokens/s
                $evalCount    = [double]$response.eval_count
                $evalDuration = [double]$response.eval_duration
                $ts = [math]::Round($evalCount / ($evalDuration / 1e9), 2)

                # TTFT in ms
                $promptEvalDuration = [double]$response.prompt_eval_duration
                $ttft = [math]::Round($promptEvalDuration / 1e6, 1)

                # Prompt evaluation t/s
                $promptTs = "N/A"
                if ($null -ne $response.prompt_eval_count -and $response.prompt_eval_count -gt 0) {
                    $promptEvalCount = [double]$response.prompt_eval_count
                    $promptTs = [math]::Round($promptEvalCount / ($promptEvalDuration / 1e9), 2)
                }

                # GPU metrics from snapshot
                $vramUsedMb   = $snap.vram_used_mb
                $sharedUsedMb = $snap.shared_used_mb
                $power        = $snap.power_w
                $temp         = $snap.temp_c
                $gpuClock     = $snap.gpu_clock_mhz
                $gpuBusyPct   = $snap.gpu_busy_pct

                # VRAM (estimated model VRAM from ollama ps)
                $vram = $modelVramMb

                # Efficiency: tokens per watt
                $efficiency = "N/A"
                if ($power -ne "N/A" -and [double]$power -gt 0) {
                    $efficiency = [math]::Round($ts / [double]$power, 3)
                }

                # Warmup label
                $warmupLabel = ""
                if ($isWarmup) { $warmupLabel = " WARMUP" }

                # Output
                $time = Get-Date -Format "HH:mm:ss"
                $tempDisplay = if ($temp -ne "N/A") { "${temp}C" } else { "N/A" }
                $powerDisplay = if ($power -ne "N/A") { "${power} W" } else { "N/A" }
                $clockDisplay = if ($gpuClock -ne "N/A") { "$gpuClock MHz" } else { "N/A" }
                $sharedDisplay = if ($sharedUsedMb -ne "N/A") { "$sharedUsedMb MB" } else { "N/A" }
                Write-Host "$time | $ts | $promptTs | $vramUsedMb MB | $powerDisplay | $tempDisplay | $clockDisplay | $sharedDisplay | $efficiency | ${gpuBusyPct}%$warmupLabel"

                # --- Save to JSONL ---
                $record = [ordered]@{
                    timestamp             = (Get-Date -Format "o")
                    ollama_version        = $ollamaVersion
                    backend               = $backend
                    model                 = $model
                    model_size            = $modelSize
                    gpu_offload           = $modelProcessor
                    num_ctx               = $numCtx
                    tokens_per_sec        = $ts
                    vram_mb               = $(if ($vram -ne "N/A") { [double]$vram } else { "N/A" })
                    power_w               = $(if ($power -ne "N/A") { [double]$power } else { "N/A" })
                    temp_c                = $(if ($temp -ne "N/A") { [int]$temp } else { "N/A" })
                    ttft_ms               = $ttft
                    gpu_clock_mhz         = $(if ($gpuClock -ne "N/A") { [int]$gpuClock } else { "N/A" })
                    vram_used_mb          = $(if ($vramUsedMb -ne "N/A") { [int]$vramUsedMb } else { "N/A" })
                    gtt_used_mb           = $(if ($sharedUsedMb -ne "N/A") { [int]$sharedUsedMb } else { "N/A" })
                    efficiency_tpw        = $(if ($efficiency -ne "N/A") { [double]$efficiency } else { "N/A" })
                    vram_baseline_mb      = $(if ($baselineVramMb -ne "N/A") { [int]$baselineVramMb } else { "N/A" })
                    gtt_baseline_mb       = $(if ($baselineSharedMb -ne "N/A") { [int]$baselineSharedMb } else { "N/A" })
                    gpu_busy_pct          = $(if ($gpuBusyPct -ne "N/A") { [int]$gpuBusyPct } else { "N/A" })
                    mem_busy_pct          = "N/A"
                    warmup                = $isWarmup
                    prompt_tokens_per_sec = $(if ($promptTs -ne "N/A") { [double]$promptTs } else { "N/A" })
                    prompt_id             = $promptId
                }
                $jsonLine = $record | ConvertTo-Json -Compress -Depth 3
                Add-Content -Path $jsonFile -Value $jsonLine -Encoding UTF8
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') | API Busy..."
            }

            Start-Sleep -Seconds 1
        }
    }

    Write-Host ""
    Write-Host "==============================================="
    Write-Host "  Benchmark complete."
    Write-Host "==============================================="
}

Ollama-Bench
