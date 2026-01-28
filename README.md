# Ollama Benchmark Scripts

Fish shell scripts for benchmarking Ollama with different GPU backends (ROCm, Vulkan) on AMD GPUs.

## Scripts

### ollama_bench.fish

Benchmark script that sweeps over multiple context sizes (`num_ctx`). Before the sweep starts, an interactive menu lets you choose a prompt category and length. For each context size the model is stopped and reloaded to ensure a clean KV cache allocation and accurate VRAM measurement. A baseline measurement captures how much VRAM/GTT is already occupied by other processes (Firefox, compositor, etc.).

#### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `model` | `qwen3-coder:30b` | Ollama model to benchmark |
| `context_sizes` | `2048 4096 8192 16384 32768` | Context lengths to sweep |
| `runs_per_ctx` | `6` | Runs per context size (1 warmup + 5 measured) |
| `card_path` | `/sys/class/drm/card1/device` | sysfs path for the GPU |

#### Prompt Selection

On startup, an interactive menu presents prompt categories and lengths:

1. **Code Generation** -- Short / Medium / Long code tasks
2. **Prose / Text** -- Short / Medium / Long text tasks
3. **Reasoning / Analysis** -- Short / Medium / Long reasoning tasks
4. **Custom Prompt** -- Enter a free-form prompt

All runs in one benchmark session use the same prompt, keeping results comparable across context sizes. The selected `prompt_id` is stored in each JSON result line.

| ID | Category | Name | Description |
|----|----------|------|-------------|
| `code_short` | Code Generation | Prime Check | Python prime check function |
| `code_medium` | Code Generation | LRU Cache | Thread-safe C++ LRU cache class |
| `code_long` | Code Generation | REST API | Go REST API with auth & middleware |
| `prose_short` | Prose / Text | Mutex Explanation | One-paragraph mutex explanation |
| `prose_medium` | Prose / Text | TCP vs UDP | Protocol comparison |
| `prose_long` | Prose / Text | GPU Architecture | Technical blog post on GPU evolution |
| `reason_short` | Reasoning | Complexity | Binary search complexity |
| `reason_medium` | Reasoning | Debug Code | Off-by-one bug analysis |
| `reason_long` | Reasoning | System Design | Distributed message queue design |
| `custom` | Custom | Custom | User-provided prompt |

#### Metrics

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

The first run after each model reload (per context size) is marked as warmup and excluded from averages in the comparison script.

The backend (Vulkan/ROCm/CUDA/native/CPU) is detected automatically via installed `pacman` packages (`ollama-vulkan`, `ollama-rocm`, `ollama-cuda`, `ollama`). Results are saved to `benchmark_<backend>.json` in JSONL format (one JSON object per line).

The script terminates after completing all context sizes -- no manual interruption needed.

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
  "num_ctx": 4096,
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
  "prompt_tokens_per_sec": 45.67,
  "prompt_id": "code_medium"
}
```

### compare-benchmarks.fish

Compares benchmark results from `benchmark_vulkan.json` and `benchmark_rocm.json`, grouped by `num_ctx`. Shows averages for all metrics per context size and the percentage speed difference. Warmup runs are excluded from all averages and TTFT is shown separately for warm and cold starts. Legacy data without `num_ctx` is grouped under "default".

```bash
./compare-benchmarks.fish
```

## Interpretation

- **GPU-Busy high (>90%), MEM-Busy moderate**: GPU is fully utilized (compute-bound)
- **GPU-Busy low, MEM-Busy high**: Memory bandwidth is the bottleneck (memory-bound)
- **High GTT value**: Model was partially offloaded to system RAM -- performance suffers
- **Efficiency (t/W)**: Higher = better. Shows how efficiently the backend uses the GPU
- **Prompt t/s >> Gen t/s**: Normal -- prompt evaluation is parallelizable, generation is sequential
- **Larger num_ctx**: Increases KV cache size, which increases VRAM usage and may affect performance

## Requirements

- Fish Shell
- Ollama (`ollama-rocm`, `ollama-vulkan`, `ollama-cuda`, or `ollama` via pacman)
- jq, curl
- AMD GPU (RDNA/CDNA) with `amdgpu` driver and sysfs support
