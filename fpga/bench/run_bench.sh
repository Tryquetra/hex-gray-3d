#!/usr/bin/env bash
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${BENCH_DIR}/out"
mkdir -p "${OUT_DIR}"

YOSYS="${YOSYS:-yosys}"
NEXTPNR="${NEXTPNR:-${HOME}/.local/bin/nextpnr-himbaechel}"
IVERILOG="${IVERILOG:-iverilog}"
VVP="${VVP:-vvp}"

echo "=== [1/3] Functional, Switching (alpha), and CDC+Skew Simulation ==="
"${IVERILOG}" -g2005 -o "${OUT_DIR}/tb_bench.vvp" "${BENCH_DIR}/bench_models.v" "${BENCH_DIR}/tb_bench.v"
"${VVP}" "${OUT_DIR}/tb_bench.vvp" | tee "${OUT_DIR}/sim_results.txt"

echo ""
echo "=== [2/3] Isolated Single-Core Gowin LUT/DFF Mapping (yosys synth_gowin) ==="
printf "%-18s %8s %8s %8s %8s\n" "Module" "LUT1-4" "MUX5/6" "ALU" "DFF"
for mod in ring_bin3 ring_onehot7 ring_trit2b ring_hex_gray3 alu_bin3 alu_onehot7 alu_trit2b alu_hex_gray3; do
  "${YOSYS}" -p "read_verilog ${BENCH_DIR}/bench_models.v; synth_gowin -top ${mod} -family gw2a; stat" \
    > "${OUT_DIR}/${mod}_yosys.log" 2>&1
  read -r luts muxs alus dffs <<< "$(awk '
    /3\. Printing statistics\./ { in_end=1 }
    in_end && ($2 ~ /^LUT[1-4]$/) { lut += $1 }
    in_end && ($2 ~ /^MUX2_LUT/) { mux += $1 }
    in_end && ($2 == "ALU") { alu += $1 }
    in_end && ($2 ~ /^DFF/) { dff += $1 }
    END { printf "%d %d %d %d\n", lut+0, mux+0, alu+0, dff+0 }
  ' "${OUT_DIR}/${mod}_yosys.log")"
  printf "%-18s %8s %8s %8s %8s\n" "${mod}" "${luts}" "${muxs}" "${alus}" "${dffs}"
done | tee "${OUT_DIR}/core_yosys_summary.txt"

echo ""
echo "=== [3/3] 64-Lane Routed Bank P&R (GW2AR-LV18QN88C8/I7 via nextpnr-himbaechel) ==="
printf "%-18s %8s %8s %8s %8s %12s\n" "Bank64" "LUT4" "ALU" "MUX2_5" "DFF" "Fmax(MHz)"
names=(bin3 onehot7 trit2b hex_gray3)
for mode in 0 1; do
  mname=$([[ "${mode}" == "0" ]] && echo "ring" || echo "alu")
  for idx in 0 1 2 3; do
    cname="${mname}_${names[$idx]}"
    "${YOSYS}" -q -p "read_verilog ${BENCH_DIR}/bench_models.v; chparam -set MODEL ${idx} -set MODE ${mode} bank64_bench; synth_gowin -top bank64_bench -family gw2a -json ${OUT_DIR}/bank_${cname}.json"
    "${NEXTPNR}" \
      --json "${OUT_DIR}/bank_${cname}.json" \
      --write "${OUT_DIR}/bank_${cname}_pnr.json" \
      --device "GW2AR-LV18QN88C8/I7" \
      --vopt family=GW2A-18C \
      --vopt cst="${BENCH_DIR}/bank64.cst" \
      > "${OUT_DIR}/bank_${cname}_pnr.log" 2>&1
    lut4=$(awk '/^\s*Info:\s+LUT4:/ || /LUT4:/ {val=$3} END{print val+0}' "${OUT_DIR}/bank_${cname}_pnr.log")
    alu=$(awk '/ALU:/ {val=$3} END{print val+0}' "${OUT_DIR}/bank_${cname}_pnr.log")
    mux5=$(awk '/MUX2_LUT5:/ {val=$3} END{print val+0}' "${OUT_DIR}/bank_${cname}_pnr.log")
    dff=$(awk '/DFF:/ {val=$3} END{print val+0}' "${OUT_DIR}/bank_${cname}_pnr.log")
    fmax=$(awk '/Max frequency for clock/ {for(i=1;i<=NF;i++) if($i=="MHz") val=$(i-1)} END{print (val=="" ? "N/A" : val)}' "${OUT_DIR}/bank_${cname}_pnr.log")
    printf "%-18s %8s %8s %8s %8s %12s\n" "${cname}" "${lut4:-0}" "${alu:-0}" "${mux5:-0}" "${dff:-0}" "${fmax:-N/A}"
  done
done | tee "${OUT_DIR}/bank64_pnr_summary.txt"
