#!/usr/bin/env fish
# Vergleicht benchmark_vulkan.csv und benchmark_rocm.csv

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               Benchmark Vergleich: Vulkan vs ROCm            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

for f in benchmark_vulkan.csv benchmark_rocm.csv
    if test -f $f
        set backend (string replace -r 'benchmark_(.+)\.csv' '$1' $f | string upper)
        set stats (tail -n +2 $f | grep -v '^$' | awk -F',' '{
            ts+=$7; vram+=$8; power+=$9; temp+=$10; ttft+=$11;
            if ($12+0 > 0) { clk+=$12; clk_n++ }
            if ($13+0 > 0) { vram_real+=$13; vram_real_n++ }
            if ($14+0 > 0) { gtt+=$14; gtt_n++ }
            n++
        } END {
            if (n>0) printf "%.2f|%.0f|%.1f|%.1f|%.1f|%d|%.0f|%.0f|%.0f", ts/n, vram/n, power/n, temp/n, ttft/n, n, (clk_n>0 ? clk/clk_n : 0), (vram_real_n>0 ? vram_real/vram_real_n : 0), (gtt_n>0 ? gtt/gtt_n : 0)
        }')

        set ts (echo $stats | cut -d'|' -f1)
        set vram (echo $stats | cut -d'|' -f2)
        set power (echo $stats | cut -d'|' -f3)
        set temp (echo $stats | cut -d'|' -f4)
        set ttft (echo $stats | cut -d'|' -f5)
        set count (echo $stats | cut -d'|' -f6)
        set gpu_clock (echo $stats | cut -d'|' -f7)
        set vram_real (echo $stats | cut -d'|' -f8)
        set gtt (echo $stats | cut -d'|' -f9)

        echo "=== $backend ($count Messungen) ==="
        echo "  Tokens/s:   $ts t/s"
        echo "  VRAM (est): $vram MB (Modell-Anteil)"
        if test "$vram_real" != "0"
            echo "  VRAM (hw):  $vram_real MB (tatsächlich belegt)"
        end
        echo "  Power:      $power W"
        echo "  Temp:       $temp °C"
        echo "  TTFT:       $ttft ms"
        if test "$gpu_clock" != "0"
            echo "  GPU-Clock:  $gpu_clock MHz (Ø max)"
        end
        if test "$gtt" != "0"
            echo "  GTT:        $gtt MB (Ø System-RAM Spillover)"
        end
        echo
    end
end

# Vergleich berechnen
set vulkan_ts (tail -n +2 benchmark_vulkan.csv | grep -v '^$' | awk -F',' '{ts+=$7; n++} END {printf "%.2f", ts/n}')
set rocm_ts (tail -n +2 benchmark_rocm.csv | grep -v '^$' | awk -F',' '{ts+=$7; n++} END {printf "%.2f", ts/n}')

set diff (echo "$vulkan_ts $rocm_ts" | awk '{printf "%.1f", (($1-$2)/$2)*100}')

echo "─────────────────────────────────────────────────────────────────"
if test (echo "$vulkan_ts > $rocm_ts" | bc) -eq 1
    echo "Vulkan ist $diff% schneller als ROCm"
else
    set diff (echo "$rocm_ts $vulkan_ts" | awk '{printf "%.1f", (($1-$2)/$2)*100}')
    echo "ROCm ist $diff% schneller als Vulkan"
end
