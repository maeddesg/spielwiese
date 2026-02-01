# ollama_bench.ps1 - Ollama Benchmark for Windows
# PowerShell port of ollama_bench.fish
# Requires: Ollama running on localhost:11434
# Optional: LibreHardwareMonitor CLI for GPU temp/power/clock monitoring

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

    $categories = @(
        @{ label = "Code Generation";      offset = 0 }
        @{ label = "Prose / Text";         offset = 3 }
        @{ label = "Reasoning / Analysis"; offset = 6 }
    )

    # --- Interactive prompt selection menu ---
    $promptId = $null
    $promptName = $null
    $promptText = $null

    while ($true) {
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

        switch ($categoryChoice) {
            "0" {
                Write-Host "Exiting."
                return
            }
            "1" { $catLabel = "Code Generation"; $catOffset = 0 }
            "2" { $catLabel = "Prose / Text";    $catOffset = 3 }
            "3" { $catLabel = "Reasoning / Analysis"; $catOffset = 6 }
            "4" {
                $customInput = Read-Host "Enter your custom prompt"
                if ([string]::IsNullOrWhiteSpace($customInput)) {
                    Write-Host "Empty prompt, try again."
                    continue
                }
                $promptId   = "custom"
                $promptName = "Custom"
                $promptText = $customInput
                break
            }
            default {
                Write-Host "Invalid selection, try again."
                continue
            }
        }

        if ($promptId) { break }

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

        switch ($lengthChoice) {
            "0" { continue }
            "1" {
                $promptId   = $prompts[$idx1].id
                $promptName = $prompts[$idx1].name
                $promptText = $prompts[$idx1].text
                break
            }
            "2" {
                $promptId   = $prompts[$idx2].id
                $promptName = $prompts[$idx2].name
                $promptText = $prompts[$idx2].text
                break
            }
            "3" {
                $promptId   = $prompts[$idx3].id
                $promptName = $prompts[$idx3].name
                $promptText = $prompts[$idx3].text
                break
            }
            default {
                Write-Host "Invalid selection, try again."
                continue
            }
        }

        if ($promptId) { break }
    }

    # --- Check if Ollama is running ---
    try {
        $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -ErrorAction Stop
    } catch {
        Write-Host "Error: Ollama is not running (port 11434)"
        return
    }

    # --- Detect backend ---
    # On Windows we detect via Ollama's GPU library environment or GPU adapter info
    $backend = "windows"
    try {
        $gpuAdapter = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | Select-Object -First 1
        if ($gpuAdapter) {
            $gpuName = $gpuAdapter.Name
            if ($gpuName -match "NVIDIA") {
                $backend = "windows-cuda"
            } elseif ($gpuName -match "AMD|Radeon") {
                $backend = "windows-amd"
            } elseif ($gpuName -match "Intel") {
                $backend = "windows-intel"
            }
        }
    } catch {
        # WMI not available, keep default
    }

    # --- Ollama version ---
    try {
        $ollamaVersionRaw = & ollama --version 2>&1
        $ollamaVersion = ($ollamaVersionRaw -replace "ollama version is ", "").Trim()
    } catch {
        $ollamaVersion = "unknown"
    }

    $jsonFile = "benchmark_$backend.json"

    # --- GPU Monitoring Setup ---
    # Try to detect available GPU monitoring methods

    # Method 1: Windows Performance Counters (GPU utilization + VRAM)
    $hasGpuCounters = $false
    try {
        $null = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop -MaxSamples 1
        $hasGpuCounters = $true
    } catch {
        # Performance counters not available
    }

    # Method 2: nvidia-smi (NVIDIA GPUs)
    $hasNvidiaSmi = $false
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $hasNvidiaSmi = $true
    }

    # --- GPU Info Helper Functions ---

    function Get-GpuMetrics {
        $metrics = @{
            vram_used_mb  = "N/A"
            vram_total_mb = "N/A"
            gpu_busy_pct  = "N/A"
            mem_busy_pct  = "N/A"
            temp_c        = "N/A"
            power_w       = "N/A"
            gpu_clock_mhz = "N/A"
        }

        # Try nvidia-smi first (most complete)
        if ($hasNvidiaSmi) {
            try {
                $smiOutput = & nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu,utilization.memory,temperature.gpu,power.draw,clocks.gr '--format=csv,noheader,nounits' 2>$null
                if ($smiOutput) {
                    $parts = $smiOutput.Split(",") | ForEach-Object { $_.Trim() }
                    if ($parts.Count -ge 7) {
                        $metrics.vram_used_mb  = [int]$parts[0]
                        $metrics.vram_total_mb = [int]$parts[1]
                        $metrics.gpu_busy_pct  = [int]$parts[2]
                        $metrics.mem_busy_pct  = [int]$parts[3]
                        $metrics.temp_c        = [int]$parts[4]
                        $metrics.power_w       = [math]::Round([double]$parts[5], 1)
                        $metrics.gpu_clock_mhz = [int]$parts[6]
                    }
                }
            } catch { }
            return $metrics
        }

        # Try Windows Performance Counters for AMD/Intel
        if ($hasGpuCounters) {
            try {
                # GPU utilization (3D engine)
                $gpuSamples = (Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                $gpuUtil = ($gpuSamples | Measure-Object -Property CookedValue -Sum).Sum
                $metrics.gpu_busy_pct = [math]::Round($gpuUtil, 0)
            } catch { }

            try {
                # Dedicated GPU memory (VRAM)
                $memSamples = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                $dedicatedBytes = ($memSamples | Measure-Object -Property CookedValue -Sum).Sum
                $metrics.vram_used_mb = [math]::Round($dedicatedBytes / 1MB, 0)
            } catch { }

            try {
                # Shared GPU memory (like GTT / system RAM spillover)
                $sharedSamples = (Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                $sharedBytes = ($sharedSamples | Measure-Object -Property CookedValue -Sum).Sum
                $metrics.mem_busy_pct = [math]::Round($sharedBytes / 1MB, 0)  # stored as shared_mb, reusing field
            } catch { }
        }

        # Try to get VRAM total from WMI
        try {
            $adapter = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | Select-Object -First 1
            if ($adapter.AdapterRAM -and $adapter.AdapterRAM -gt 0) {
                $metrics.vram_total_mb = [math]::Round([uint64]$adapter.AdapterRAM / 1MB, 0)
            }
        } catch { }

        return $metrics
    }

    # --- Stop model for clean baseline ---
    Write-Host "Stopping model $model for clean baseline..."
    & ollama stop $model 2>$null
    Start-Sleep -Seconds 2

    # Baseline GPU metrics
    $baselineMetrics = Get-GpuMetrics
    $baselineVramMb = $baselineMetrics.vram_used_mb
    $vramTotalMb    = $baselineMetrics.vram_total_mb

    # Create JSON file if it doesn't exist
    if (-not (Test-Path $jsonFile)) {
        $null = New-Item -Path $jsonFile -ItemType File -Force
    }

    Write-Host "==============================================="
    Write-Host "  Ollama Benchmark (Windows)"
    Write-Host "==============================================="
    Write-Host "Ollama:   $ollamaVersion"
    Write-Host "Backend:  $backend"
    Write-Host "Model:    $model"
    Write-Host "Contexts: $($contextSizes -join ', ')"
    Write-Host "Runs:     $runsPerCtx per context size (1 warmup + $($runsPerCtx - 1) measured)"
    Write-Host "Prompt:   $promptName ($promptId)"
    Write-Host "JSON:     $jsonFile"
    if ($hasNvidiaSmi)   { Write-Host "GPU Mon:  nvidia-smi (full metrics)" }
    elseif ($hasGpuCounters) { Write-Host "GPU Mon:  Windows Performance Counters (VRAM + GPU%)" }
    else { Write-Host "GPU Mon:  Limited (no nvidia-smi or perf counters)" }
    Write-Host "==============================================="

    # --- Ctrl+C handler ---
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        Write-Host "`nBenchmark interrupted."
    }

    foreach ($numCtx in $contextSizes) {
        # Stop model before each context size for clean KV cache
        Write-Host ""
        Write-Host "--- Stopping model for context size $numCtx ---"
        & ollama stop $model 2>$null
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
            $null = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $loadBody -ContentType "application/json" -ErrorAction Stop
        } catch {
            Write-Host "Warning: Failed to pre-load model: $_"
        }

        # Measure VRAM after loading
        $loadedMetrics = Get-GpuMetrics
        $loadedVramMb  = $loadedMetrics.vram_used_mb

        # Calculate delta
        if ($baselineVramMb -ne "N/A" -and $loadedVramMb -ne "N/A") {
            $deltaVramMb = $loadedVramMb - $baselineVramMb
        } else {
            $deltaVramMb = "N/A"
        }

        # Get model info from ollama ps
        $modelSize      = "N/A"
        $modelProcessor = "N/A"
        $modelVramMb    = "N/A"
        try {
            $psOutput = & ollama ps 2>$null
            $modelLine = $psOutput | Where-Object { $_ -match [regex]::Escape($model) }
            if ($modelLine) {
                # Parse: NAME  ID  SIZE  PROCESSOR  UNTIL
                # Example: qwen3-coder:30b  abc123  18 GB  23%/77%  4 minutes from now
                if ($modelLine -match '(\d+\.?\d*)\s+(GB|MB)\s+(\d+%/\d+%)') {
                    $sizeNum  = [double]$Matches[1]
                    $sizeUnit = $Matches[2]
                    $modelSize = "${sizeNum}_${sizeUnit}"
                    $processorRaw = $Matches[3]
                    $pctParts = $processorRaw -split "/"
                    $cpuPct = $pctParts[0]
                    $gpuPct = $pctParts[1]
                    $modelProcessor = "$cpuPct (RAM) / $gpuPct (VRAM)"

                    $gpuPctNum = [int]($gpuPct -replace "%", "")
                    if ($sizeUnit -eq "GB") {
                        $modelSizeMb = $sizeNum * 1024
                    } else {
                        $modelSizeMb = $sizeNum
                    }
                    $modelVramMb = [math]::Round($modelSizeMb * $gpuPctNum / 100, 0)
                }
            }
        } catch { }

        Write-Host "-------------------------------------------------------------------------------------------------------------------"
        Write-Host "  num_ctx=$numCtx | Size: $modelSize | Offload: $modelProcessor"
        Write-Host "  VRAM: $vramTotalMb MB total | Baseline: $baselineVramMb MB | Model: +$deltaVramMb MB | Loaded: $loadedVramMb MB"
        Write-Host "-------------------------------------------------------------------------------------------------------------------"
        Write-Host "Time     | Gen t/s | Prompt t/s | VRAM    | Power | Temp  | Clock   | t/W   | GPU%  | MEM%  |"
        Write-Host "-------------------------------------------------------------------------------------------------------------------"

        for ($run = 1; $run -le $runsPerCtx; $run++) {
            $isWarmup = ($run -eq 1)

            # --- Background GPU sampler (PowerShell Job) ---
            $samplerScript = {
                param($hasNvidiaSmi, $hasGpuCounters)
                $samples = [System.Collections.ArrayList]::new()
                while ($true) {
                    $s = @{
                        timestamp     = [datetime]::Now
                        power_w       = "N/A"
                        temp_c        = "N/A"
                        gpu_clock_mhz = "N/A"
                        gpu_busy_pct  = "N/A"
                        vram_used_mb  = "N/A"
                        shared_mb     = "N/A"
                    }

                    if ($hasNvidiaSmi) {
                        try {
                            $out = & nvidia-smi --query-gpu=memory.used,utilization.gpu,utilization.memory,temperature.gpu,power.draw,clocks.gr '--format=csv,noheader,nounits' 2>$null
                            if ($out) {
                                $p = $out.Split(",") | ForEach-Object { $_.Trim() }
                                $s.vram_used_mb  = [int]$p[0]
                                $s.gpu_busy_pct  = [int]$p[1]
                                $s.shared_mb     = [int]$p[2]
                                $s.temp_c        = [int]$p[3]
                                $s.power_w       = [math]::Round([double]$p[4], 1)
                                $s.gpu_clock_mhz = [int]$p[5]
                            }
                        } catch { }
                    }
                    elseif ($hasGpuCounters) {
                        try {
                            $gpuSamples = (Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                            $s.gpu_busy_pct = [math]::Round(($gpuSamples | Measure-Object -Property CookedValue -Sum).Sum, 0)
                        } catch { }
                        try {
                            $memSamples = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                            $s.vram_used_mb = [math]::Round(($memSamples | Measure-Object -Property CookedValue -Sum).Sum / 1MB, 0)
                        } catch { }
                        try {
                            $sharedSamples = (Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop -MaxSamples 1).CounterSamples
                            $s.shared_mb = [math]::Round(($sharedSamples | Measure-Object -Property CookedValue -Sum).Sum / 1MB, 0)
                        } catch { }
                    }

                    $null = $samples.Add([PSCustomObject]$s)
                    Start-Sleep -Milliseconds 200
                }
                # This won't be reached but the samples are in the job's output
            }

            $samplerJob = Start-Job -ScriptBlock $samplerScript -ArgumentList $hasNvidiaSmi, $hasGpuCounters

            # --- Run inference ---
            $body = @{
                model   = $model
                prompt  = $promptText
                stream  = $false
                options = @{ num_ctx = $numCtx }
            } | ConvertTo-Json -Depth 3

            $response = $null
            try {
                $response = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
            } catch {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') | API Error: $_"
            }

            # --- Stop sampler and collect samples ---
            Stop-Job -Job $samplerJob -ErrorAction SilentlyContinue
            # Retrieve partial output from the job
            $samplerOutput = Receive-Job -Job $samplerJob -ErrorAction SilentlyContinue
            Remove-Job -Job $samplerJob -Force -ErrorAction SilentlyContinue

            # Take a snapshot of GPU metrics right now
            $snapshotMetrics = Get-GpuMetrics

            if ($response -and $response.eval_count -and $response.eval_count -gt 0) {
                # Generation tokens/s
                $evalCount    = [double]$response.eval_count
                $evalDuration = [double]$response.eval_duration
                $ts = [math]::Round($evalCount / ($evalDuration / 1e9), 2)

                # TTFT in ms
                $promptEvalDuration = [double]$response.prompt_eval_duration
                $ttft = [math]::Round($promptEvalDuration / 1e6, 1)

                # Prompt evaluation t/s
                $promptTs = "N/A"
                if ($response.prompt_eval_count -and $response.prompt_eval_count -gt 0) {
                    $promptEvalCount = [double]$response.prompt_eval_count
                    $promptTs = [math]::Round($promptEvalCount / ($promptEvalDuration / 1e9), 2)
                }

                # GPU metrics from snapshot
                $vramUsedMb  = $snapshotMetrics.vram_used_mb
                $power       = $snapshotMetrics.power_w
                $temp        = $snapshotMetrics.temp_c
                $gpuClock    = $snapshotMetrics.gpu_clock_mhz
                $gpuBusyAvg  = $snapshotMetrics.gpu_busy_pct
                $memBusyAvg  = $snapshotMetrics.mem_busy_pct

                # VRAM (estimated model VRAM)
                $vram = $modelVramMb

                # Efficiency: tokens per watt
                $efficiency = "N/A"
                if ($power -ne "N/A" -and $power -ne 0) {
                    $efficiency = [math]::Round($ts / [double]$power, 3)
                }

                # Warmup label
                $warmupLabel = ""
                if ($isWarmup) { $warmupLabel = " WARMUP" }

                # Output
                $time = Get-Date -Format "HH:mm:ss"
                Write-Host "$time | $ts | $promptTs | $vramUsedMb MB | $power W | ${temp}C | $gpuClock MHz | $efficiency | $gpuBusyAvg% | ${memBusyAvg}%$warmupLabel"

                # --- Save to JSONL ---
                $record = [ordered]@{
                    timestamp            = (Get-Date -Format "o")
                    ollama_version       = $ollamaVersion
                    backend              = $backend
                    model                = $model
                    model_size           = $modelSize
                    gpu_offload          = $modelProcessor
                    num_ctx              = $numCtx
                    tokens_per_sec       = $ts
                    vram_mb              = if ($vram -ne "N/A") { [double]$vram } else { "N/A" }
                    power_w              = if ($power -ne "N/A") { [double]$power } else { "N/A" }
                    temp_c               = if ($temp -ne "N/A") { [int]$temp } else { "N/A" }
                    ttft_ms              = $ttft
                    gpu_clock_mhz        = if ($gpuClock -ne "N/A") { [int]$gpuClock } else { "N/A" }
                    vram_used_mb         = if ($vramUsedMb -ne "N/A") { [int]$vramUsedMb } else { "N/A" }
                    gtt_used_mb          = "N/A"
                    efficiency_tpw       = if ($efficiency -ne "N/A") { [double]$efficiency } else { "N/A" }
                    vram_baseline_mb     = if ($baselineVramMb -ne "N/A") { [int]$baselineVramMb } else { "N/A" }
                    gtt_baseline_mb      = "N/A"
                    gpu_busy_pct         = if ($gpuBusyAvg -ne "N/A") { [int]$gpuBusyAvg } else { "N/A" }
                    mem_busy_pct         = if ($memBusyAvg -ne "N/A") { [int]$memBusyAvg } else { "N/A" }
                    warmup               = $isWarmup
                    prompt_tokens_per_sec = if ($promptTs -ne "N/A") { [double]$promptTs } else { "N/A" }
                    prompt_id            = $promptId
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
