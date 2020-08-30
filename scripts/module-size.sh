#!/bin/bash

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 module..."
    exit 1
fi

echo "    Module    Cells  EBR  SPRAM   RAM4K  RAM4KNR    CARRY  LUT4   DFF"
echo "    ------    -----------------   -----------------------------------"
for module in "$@"; do
    printf "%10s    " $module
    yosys -DSYNTHESIS -p "synth_ice40" "${module}.v" | \
        awk '/Number of cells:/ { cells = $NF }
            /SB_RAM40_4K *[0-9]+/ { ram_4k = $NF; ebr += $NF }
            /SB_RAM40_4KNR *[0-9]+/ { ram_4knr = $NF; ebr += $NF }
            /SB_SPRAM256KA *[0-9]+/ { spram = $NF }
            /SB_CARRY *[0-9]+/ { carry = $NF }
            /SB_LUT4 *[0-9]+/ { lut4 = $NF }
            /SB_DFF.*[0-9]+/ { dff += $NF }
            BEGIN { ebr = 0; spram = 0; ram_4k = 0; ram_4knr = 0; dff = 0 }
            END { printf "%5s  %3s  %5s   %5s  %7s    %5s  %4s  %4s\n",
                    cells, ebr, spram, ram_4k, ram_4knr, carry, lut4, dff }'
done
