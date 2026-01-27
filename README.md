# Ollama Benchmark Scripts

Fish shell scripts for benchmarking Ollama with different GPU backends (ROCm, Vulkan) on AMD GPUs.

## Scripts

### ollama_bench.fish

Continuous benchmark script for Ollama. Before each session the model is stopped and reloaded to ensure a clean VRAM state. A baseline measurement captures how much VRAM/GTT is already occupied by other processes (Firefox, compositor, etc.).

Metrics sampled per inference run:

| Metric | Source | Description |
|--------|--------|-------------|
| **Tokens/s** | Ollama API | Generation speed |
| **VRAM (hw)** | `mem_info_vram_used` | Actual VRAM usage from hardware |
| **Power** | `power1_average` | GPU power consumption (peak, Watts) |
| **Temperature** | `temp1_input` | GPU temperature |
| **TTFT** | Ollama API | Time to First Token (ms) |
| **GPU-Clock** | `pp_dpm_sclk` | Shader clock during inference (peak, MHz) |
| **GTT** | `mem_info_gtt_used` | System-RAM spillover (peak, MB) |
| **Effizienz** | berechnet | Tokens pro Joule (t/s / W) |
| **GPU-Busy** | `gpu_busy_percent` | GPU-Auslastung (Durchschnitt, %) |
| **MEM-Busy** | `mem_busy_percent` | Speicherbus-Auslastung (Durchschnitt, %) |

Power, Clock, GTT, GPU-Busy und MEM-Busy werden alle 100ms im Hintergrund gesampled.

The backend (ROCm/Vulkan/CPU) is detected automatically via installed `pacman` packages. Results are saved to `benchmark_<backend>.csv`.

```bash
./ollama_bench.fish
```

#### CSV-Spalten

```
timestamp, ollama_version, backend, model, model_size, gpu_offload,
tokens_per_sec, vram_mb, power_w, temp_c, ttft_ms, gpu_clock_mhz,
vram_used_mb, gtt_used_mb, efficiency_tpj, vram_baseline_mb,
gtt_baseline_mb, gpu_busy_pct, mem_busy_pct
```

### compare-benchmarks.fish

Compares benchmark results from Vulkan and ROCm, showing averages for all metrics and the percentage speed difference.

```bash
./compare-benchmarks.fish
```

## Interpretation

- **GPU-Busy hoch (>90%), MEM-Busy moderat**: GPU wird voll ausgelastet (compute-bound)
- **GPU-Busy niedrig, MEM-Busy hoch**: Speicherbandbreite ist der Flaschenhals (memory-bound)
- **Hoher GTT-Wert**: Modell wurde teilweise in System-RAM ausgelagert -- Performance leidet
- **Effizienz (t/J)**: Höher = besser. Zeigt wie effizient das Backend die GPU nutzt

## Requirements

- Fish Shell
- Ollama (`ollama-rocm` or `ollama-vulkan` via pacman)
- jq, curl
- AMD GPU (RDNA/CDNA) with `amdgpu` driver and sysfs support
