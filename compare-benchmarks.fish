#!/usr/bin/env fish
# Vergleicht benchmark_vulkan.csv und benchmark_rocm.csv

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               Benchmark Vergleich: Vulkan vs ROCm            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

for f in benchmark_vulkan.csv benchmark_rocm.csv
    if test -f $f
        set backend (string replace -r 'benchmark_(.+)\.csv' '$1' $f | string upper)

        # Warmup-Zeilen zählen
        set warmup_count (tail -n +2 $f | grep -v '^$' | awk -F',' '$20 == "true" {n++} END {printf "%d", n+0}')

        # Statistik nur aus Nicht-Warmup-Zeilen (Spalte 20 != "true")
        # Fallback: Zeilen ohne Spalte 20 werden einbezogen (alte Daten)
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
                n++
            }
        END {
            if (n>0) printf "%.2f|%.0f|%.1f|%.1f|%.1f|%d|%.0f|%.0f|%.0f|%.3f|%.0f|%.0f|%.0f|%.0f", ts/n, vram/n, power/n, temp/n, ttft/n, n, (clk_n>0 ? clk/clk_n : 0), (vram_real_n>0 ? vram_real/vram_real_n : 0), (gtt_n>0 ? gtt/gtt_n : 0), (eff_n>0 ? eff/eff_n : (power/n>0 ? ts/n/(power/n) : 0)), (bl_n>0 ? bl_vram/bl_n : 0), (bl_gtt_n>0 ? bl_gtt/bl_gtt_n : 0), (gpu_b_n>0 ? gpu_b/gpu_b_n : 0), (mem_b_n>0 ? mem_b/mem_b_n : 0)
        }')

        # Warmup-TTFT separat berechnen
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

        echo "=== $backend ($count Messungen, $warmup_count Warmup übersprungen) ==="
        echo "  Tokens/s:   $ts t/s"
        echo "  VRAM (est): $vram MB (Modell-Anteil)"
        if test "$vram_real" != "0"
            echo "  VRAM (hw):  $vram_real MB (tatsächlich belegt)"
        end
        if test "$bl_vram" != "0"
            echo "  VRAM Base:  $bl_vram MB (Ø Baseline ohne Modell)"
        end
        echo "  Power:      $power W"
        echo "  Temp:       $temp °C"
        echo "  TTFT:       $ttft ms (warm) | $warmup_ttft ms (kalt/Warmup)"
        if test "$gpu_clock" != "0"
            echo "  GPU-Clock:  $gpu_clock MHz (Ø max)"
        end
        if test "$gtt" != "0"
            echo "  GTT:        $gtt MB (Ø System-RAM Spillover)"
        end
        if test "$bl_gtt" != "0"
            echo "  GTT Base:   $bl_gtt MB (Ø Baseline ohne Modell)"
        end
        echo "  Effizienz:  $efficiency t/J (Tokens pro Joule)"
        if test "$gpu_busy" != "0"
            echo "  GPU-Busy:   $gpu_busy% (Ø Shader-Auslastung)"
        end
        if test "$mem_busy" != "0"
            echo "  MEM-Busy:   $mem_busy% (Ø Speicherbus-Auslastung)"
        end
        echo
    end
end

# Vergleich berechnen (ohne Warmup)
set vulkan_ts (tail -n +2 benchmark_vulkan.csv 2>/dev/null | grep -v '^$' | awk -F',' '$20 != "true" {ts+=$7; n++} END {if(n>0) printf "%.2f", ts/n; else print "0"}')
set rocm_ts (tail -n +2 benchmark_rocm.csv 2>/dev/null | grep -v '^$' | awk -F',' '$20 != "true" {ts+=$7; n++} END {if(n>0) printf "%.2f", ts/n; else print "0"}')

if test "$vulkan_ts" = "0"; or test "$rocm_ts" = "0"
    echo "─────────────────────────────────────────────────────────────────"
    echo "Vergleich nicht möglich (Daten für beide Backends nötig)"
else
    set diff (echo "$vulkan_ts $rocm_ts" | awk '{printf "%.1f", (($1-$2)/$2)*100}')

    echo "─────────────────────────────────────────────────────────────────"
    echo "(Warmup-Runs sind aus dem Vergleich ausgeschlossen)"
    if test (echo "$vulkan_ts > $rocm_ts" | bc) -eq 1
        echo "Vulkan ist $diff% schneller als ROCm"
    else
        set diff (echo "$rocm_ts $vulkan_ts" | awk '{printf "%.1f", (($1-$2)/$2)*100}')
        echo "ROCm ist $diff% schneller als Vulkan"
    end
end
