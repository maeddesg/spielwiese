#!/usr/bin/env fish
# Compares benchmark_vulkan.csv and benchmark_rocm.csv

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Benchmark Comparison: Vulkan vs ROCm            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

for f in benchmark_vulkan.csv benchmark_rocm.csv
    if test -f $f
        set backend (string replace -r 'benchmark_(.+)\.csv' '$1' $f | string upper)

        # Count warmup rows
        set warmup_count (tail -n +2 $f | grep -v '^$' | awk -F',' '$20 == "true" {n++} END {printf "%d", n+0}')

        # Stats from non-warmup rows only (column 20 != "true")
        # Fallback: rows without column 20 are included (legacy data)
        set stats (tail -n +2 $f | grep -v '^$' | awk -F',' '
            $20 != "true" {
                ts+=$7; vram+=$8; power+=$9; temp+=$10; ttft+=$11;
                if ($12+0 > 0) { clk+=$12; clk_n++ }
                if ($13+0 > 0) { vram_real+=$13; vram_real_n++ }
                if ($14+0 > 0) { gtt+=$14; gtt_n++ }
                if ($15+0 > 0) { eff+=$15; eff_n++ }
                if ($16+0 > 0) { bl_vram+=$16; bl_n++ }
                if ($17+0 > 0) { bl_gtt+=$17; bl_gtt_n++ }
                if ($18+0 > 0) { gpu_b+=$18; gpu_b_n++ }
                if ($19+0 > 0) { mem_b+=$19; mem_b_n++ }
                if ($21+0 > 0) { pts+=$21; pts_n++ }
                n++
            }
        END {
            if (n>0) printf "%.2f|%.0f|%.1f|%.1f|%.1f|%d|%.0f|%.0f|%.0f|%.3f|%.0f|%.0f|%.0f|%.0f|%.2f", ts/n, vram/n, power/n, temp/n, ttft/n, n, (clk_n>0 ? clk/clk_n : 0), (vram_real_n>0 ? vram_real/vram_real_n : 0), (gtt_n>0 ? gtt/gtt_n : 0), (eff_n>0 ? eff/eff_n : (power/n>0 ? ts/n/(power/n) : 0)), (bl_n>0 ? bl_vram/bl_n : 0), (bl_gtt_n>0 ? bl_gtt/bl_gtt_n : 0), (gpu_b_n>0 ? gpu_b/gpu_b_n : 0), (mem_b_n>0 ? mem_b/mem_b_n : 0), (pts_n>0 ? pts/pts_n : 0)
        }')

        # Calculate warmup TTFT separately
        set warmup_ttft (tail -n +2 $f | grep -v '^$' | awk -F',' '$20 == "true" {ttft+=$11; n++} END {if(n>0) printf "%.1f", ttft/n; else printf "N/A"}')

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
set vulkan_ts (tail -n +2 benchmark_vulkan.csv 2>/dev/null | grep -v '^$' | awk -F',' '$20 != "true" {ts+=$7; n++} END {if(n>0) printf "%.2f", ts/n; else print "0"}')
set rocm_ts (tail -n +2 benchmark_rocm.csv 2>/dev/null | grep -v '^$' | awk -F',' '$20 != "true" {ts+=$7; n++} END {if(n>0) printf "%.2f", ts/n; else print "0"}')

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
