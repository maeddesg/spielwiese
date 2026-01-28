# Ollama Benchmark Scripts

Fish shell scripts for benchmarking Ollama with different GPU backends (ROCm, Vulkan) on AMD GPUs.

## Scripts

### ollama_bench.fish

Continuous benchmark script for Ollama. Before each session the model is stopped and reloaded to ensure a clean VRAM state. A baseline measurement captures how much VRAM/GTT is already occupied by other processes (Firefox, compositor, etc.).

Metrics sampled per inference run:

| Metric | Source | Description |
|--------|--------|-------------|
| **Gen t/s** | Ollama API | Generation speed (token output) |
| **Prompt t/s** | Ollama API | Prompt evaluation speed (token input) |
| **VRAM (hw)** | `mem_info_vram_used` | Actual VRAM usage from hardware |
| **Power** | `power1_average` | GPU power consumption (peak, watts) |
| **Temperature** | `temp1_input` | GPU temperature |
| **TTFT** | Ollama API | Time to first token (ms) |
| **GPU-Clock** | `pp_dpm_sclk` | Shader clock during inference (peak, MHz) |
| **GTT** | `mem_info_gtt_used` | System RAM spillover (peak, MB) |
| **Efficiency** | calculated | Tokens per watt (t/s / W) |
| **GPU-Busy** | `gpu_busy_percent` | GPU utilization (average, %) |
| **MEM-Busy** | `mem_busy_percent` | Memory bus utilization (average, %) |

Power, clock, GTT, GPU-Busy and MEM-Busy are sampled every 100ms in the background.

The first run after model reload is marked as warmup and excluded from averages in the comparison script.

The backend (ROCm/Vulkan/CPU) is detected automatically via installed `pacman` packages. Results are saved to `benchmark_<backend>.json` in JSONL format (one JSON object per line).

```bash
./ollama_bench.fish
```

#### JSON Fields

Each line in the output file is a JSON object with these fields:

```json
{
  "timestamp": "2026-01-27T14:30:00+01:00",
  "ollama_version": "0.9.x",
  "backend": "vulkan",
  "model": "qwen3-coder:30b",
  "model_size": "17_GB",
  "gpu_offload": "23% (RAM) / 77% (VRAM)",
  "tokens_per_sec": 51.23,
  "vram_mb": 12345,
  "power_w": 65.3,
  "temp_c": 72,
  "ttft_ms": 123.4,
  "gpu_clock_mhz": 2400,
  "vram_used_mb": 5678,
  "gtt_used_mb": 1234,
  "efficiency_tpw": 0.789,
  "vram_baseline_mb": 500,
  "gtt_baseline_mb": 200,
  "gpu_busy_pct": 95,
  "mem_busy_pct": 30,
  "warmup": false,
  "prompt_tokens_per_sec": 45.67
}
```

### compare-benchmarks.fish

Compares benchmark results from `benchmark_vulkan.json` and `benchmark_rocm.json`, showing averages for all metrics and the percentage speed difference. Warmup runs are excluded from all averages and TTFT is shown separately for warm and cold starts.

```bash
./compare-benchmarks.fish
```

## Interpretation

- **GPU-Busy high (>90%), MEM-Busy moderate**: GPU is fully utilized (compute-bound)
- **GPU-Busy low, MEM-Busy high**: Memory bandwidth is the bottleneck (memory-bound)
- **High GTT value**: Model was partially offloaded to system RAM -- performance suffers
- **Efficiency (t/W)**: Higher = better. Shows how efficiently the backend uses the GPU
- **Prompt t/s >> Gen t/s**: Normal -- prompt evaluation is parallelizable, generation is sequential

## Requirements

- Fish Shell
- Ollama (`ollama-rocm` or `ollama-vulkan` via pacman)
- jq, curl
- AMD GPU (RDNA/CDNA) with `amdgpu` driver and sysfs support
