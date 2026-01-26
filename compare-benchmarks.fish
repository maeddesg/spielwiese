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
            ts+=$7; vram+=$8; power+=$9; temp+=$10; ttft+=$11; n++
        } END {
            if (n>0) printf "%.2f|%.0f|%.1f|%.1f|%.1f|%d", ts/n, vram/n, power/n, temp/n, ttft/n, n
        }')

        set ts (echo $stats | cut -d'|' -f1)
        set vram (echo $stats | cut -d'|' -f2)
        set power (echo $stats | cut -d'|' -f3)
        set temp (echo $stats | cut -d'|' -f4)
        set ttft (echo $stats | cut -d'|' -f5)
        set count (echo $stats | cut -d'|' -f6)

        echo "=== $backend ($count Messungen) ==="
        echo "  Tokens/s:  $ts t/s"
        echo "  VRAM:      $vram MB"
        echo "  Power:     $power W"
        echo "  Temp:      $temp °C"
        echo "  TTFT:      $ttft ms"
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
