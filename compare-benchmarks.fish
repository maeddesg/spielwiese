#!/usr/bin/env fish
# Compares benchmark_vulkan.json and benchmark_rocm.json

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Benchmark Comparison: Vulkan vs ROCm            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

for f in benchmark_vulkan.json benchmark_rocm.json
    if test -f $f
        set backend (string replace -r 'benchmark_(.+)\.json' '$1' $f | string upper)

        # Count warmup rows
        set warmup_count (jq -s '[.[] | select(.warmup == true)] | length' $f)

        # Stats from non-warmup rows only
        set stats (jq -s -r '
            [.[] | select(.warmup != true)] |
            if length == 0 then empty else
            {
                ts: ([.[].tokens_per_sec | numbers] | add / length),
                vram: ([.[].vram_mb | numbers] | add / length),
                power: ([.[].power_w | numbers] | add / length),
                temp: ([.[].temp_c | numbers] | add / length),
                ttft: ([.[].ttft_ms | numbers] | add / length),
                count: length,
                gpu_clock: (if ([.[].gpu_clock_mhz | numbers] | length) > 0 then ([.[].gpu_clock_mhz | numbers] | add / length) else 0 end),
                vram_real: (if ([.[].vram_used_mb | numbers] | length) > 0 then ([.[].vram_used_mb | numbers] | add / length) else 0 end),
                gtt: (if ([.[].gtt_used_mb | numbers] | length) > 0 then ([.[].gtt_used_mb | numbers] | add / length) else 0 end),
                efficiency: (if ([.[].efficiency_tpw | numbers] | length) > 0 then ([.[].efficiency_tpw | numbers] | add / length) else 0 end),
                bl_vram: (if ([.[].vram_baseline_mb | numbers] | length) > 0 then ([.[].vram_baseline_mb | numbers] | add / length) else 0 end),
                bl_gtt: (if ([.[].gtt_baseline_mb | numbers] | length) > 0 then ([.[].gtt_baseline_mb | numbers] | add / length) else 0 end),
                gpu_busy: (if ([.[].gpu_busy_pct | numbers] | length) > 0 then ([.[].gpu_busy_pct | numbers] | add / length) else 0 end),
                mem_busy: (if ([.[].mem_busy_pct | numbers] | length) > 0 then ([.[].mem_busy_pct | numbers] | add / length) else 0 end),
                prompt_ts: (if ([.[].prompt_tokens_per_sec | numbers] | length) > 0 then ([.[].prompt_tokens_per_sec | numbers] | add / length) else 0 end)
            } |
            "\(.ts * 100 | round / 100)|\(.vram | round)|\(.power * 10 | round / 10)|\(.temp * 10 | round / 10)|\(.ttft * 10 | round / 10)|\(.count)|\(.gpu_clock | round)|\(.vram_real | round)|\(.gtt | round)|\(.efficiency * 1000 | round / 1000)|\(.bl_vram | round)|\(.bl_gtt | round)|\(.gpu_busy | round)|\(.mem_busy | round)|\(.prompt_ts * 100 | round / 100)"
            end
        ' $f)

        # Calculate warmup TTFT separately
        set warmup_ttft (jq -s -r '
            [.[] | select(.warmup == true) | .ttft_ms | numbers] |
            if length > 0 then (add / length | . * 10 | round / 10 | tostring) else "N/A" end
        ' $f)

        set ts (echo $stats | cut -d'|' -f1)
        set vram (echo $stats | cut -d'|' -f2)
        set power (echo $stats | cut -d'|' -f3)
        set temp (echo $stats | cut -d'|' -f4)
        set ttft (echo $stats | cut -d'|' -f5)
        set count (echo $stats | cut -d'|' -f6)
        set gpu_clock (echo $stats | cut -d'|' -f7)
        set vram_real (echo $stats | cut -d'|' -f8)
        set gtt (echo $stats | cut -d'|' -f9)
        set efficiency (echo $stats | cut -d'|' -f10)
        set bl_vram (echo $stats | cut -d'|' -f11)
        set bl_gtt (echo $stats | cut -d'|' -f12)
        set gpu_busy (echo $stats | cut -d'|' -f13)
        set mem_busy (echo $stats | cut -d'|' -f14)
        set prompt_ts (echo $stats | cut -d'|' -f15)

        echo "=== $backend ($count runs, $warmup_count warmup skipped) ==="
        echo "  Gen t/s:    $ts t/s (generation)"
        if test "$prompt_ts" != "0.00"; and test "$prompt_ts" != "0"
            echo "  Prompt t/s: $prompt_ts t/s (prompt evaluation)"
        end
        echo "  VRAM (est): $vram MB (model share)"
        if test "$vram_real" != "0"
            echo "  VRAM (hw):  $vram_real MB (actual usage)"
        end
        if test "$bl_vram" != "0"
            echo "  VRAM Base:  $bl_vram MB (avg baseline without model)"
        end
        echo "  Power:      $power W"
        echo "  Temp:       $temp °C"
        echo "  TTFT:       $ttft ms (warm) | $warmup_ttft ms (cold/warmup)"
        if test "$gpu_clock" != "0"
            echo "  GPU-Clock:  $gpu_clock MHz (avg peak)"
        end
        if test "$gtt" != "0"
            echo "  GTT:        $gtt MB (avg system RAM spillover)"
        end
        if test "$bl_gtt" != "0"
            echo "  GTT Base:   $bl_gtt MB (avg baseline without model)"
        end
        echo "  Efficiency: $efficiency t/W (tokens per watt)"
        if test "$gpu_busy" != "0"
            echo "  GPU-Busy:   $gpu_busy% (avg shader utilization)"
        end
        if test "$mem_busy" != "0"
            echo "  MEM-Busy:   $mem_busy% (avg memory bus utilization)"
        end
        echo
    end
end

# Calculate comparison (excluding warmup)
if test -f benchmark_vulkan.json
    set vulkan_ts (jq -s -r '[.[] | select(.warmup != true) | .tokens_per_sec | numbers] | if length > 0 then (add / length | tostring) else "0" end' benchmark_vulkan.json)
else
    set vulkan_ts "0"
end

if test -f benchmark_rocm.json
    set rocm_ts (jq -s -r '[.[] | select(.warmup != true) | .tokens_per_sec | numbers] | if length > 0 then (add / length | tostring) else "0" end' benchmark_rocm.json)
else
    set rocm_ts "0"
end

if test "$vulkan_ts" = "0"; or test "$rocm_ts" = "0"
    echo "─────────────────────────────────────────────────────────────────"
    echo "Comparison not possible (data for both backends required)"
else
    set diff (echo "$vulkan_ts $rocm_ts" | awk '{printf "%.1f", (($1-$2)/$2)*100}')

    echo "─────────────────────────────────────────────────────────────────"
    echo "(Warmup runs are excluded from comparison)"
    if test (echo "$vulkan_ts > $rocm_ts" | bc) -eq 1
        echo "Vulkan is $diff% faster than ROCm"
    else
        set diff (echo "$rocm_ts $vulkan_ts" | awk '{printf "%.1f", (($1-$2)/$2)*100}')
        echo "ROCm is $diff% faster than Vulkan"
    end
end
