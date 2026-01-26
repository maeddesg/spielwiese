# Ollama Benchmark Scripts

Fish shell scripts for benchmarking Ollama with different GPU backends (ROCm, Vulkan).

## Scripts

### ollama_bench.fish

Continuous benchmark script for Ollama. Measures on each inference:

- **Tokens/s** - Generation speed
- **VRAM** - Model GPU memory usage
- **Power** - GPU power consumption (Watts)
- **Temperature** - GPU temperature
- **TTFT** - Time to First Token (ms)

The backend (ROCm/Vulkan/CPU) is detected automatically. Results are saved to `benchmark_<backend>.csv`.

```bash
./ollama_bench.fish
```

### compare-benchmarks.fish

Compares benchmark results from Vulkan and ROCm, showing averages and the percentage speed difference.

```bash
./compare-benchmarks.fish
```

## Requirements

- Fish Shell
- Ollama (ollama-rocm or ollama-vulkan)
- jq, curl
- AMD GPU with ROCm or Vulkan support
