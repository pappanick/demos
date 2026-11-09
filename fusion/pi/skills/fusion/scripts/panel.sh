#!/usr/bin/env bash
# Run the whole Fusion panel in parallel and print a roll-call summary.
#
# Usage:
#   panel.sh <run-dir> <plan|review|write> [seats...] [-- pass-through...]
#   panel.sh .fusion/runs/20260101-120000 review kimi glm codex
#   panel.sh <run-dir> plan -- --timeout 600
#
# Default seats: kimi glm qwen deepseek agy codex (FUSION_SEATS overrides).
# Quorum: FUSION_QUORUM, default 3. Prints DEGRADED when fewer seats return blocks.
#
# The judge must still read every results/<seat>.md itself. This script never
# summarizes a block and never writes LEDGER.md.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
run_dir=${1:?usage: panel.sh <run-dir> <plan|review|write> [seats...]}
mode=${2:?missing mode}
shift 2

seats=()
while [ $# -gt 0 ]; do
  case $1 in
    --) shift; break ;;
    -*) echo "panel.sh: unknown option $1" >&2; exit 2 ;;
    *) seats+=("$1"); shift ;;
  esac
done
[ ${#seats[@]} -eq 0 ] && read -r -a seats <<<"${FUSION_SEATS:-kimi glm qwen deepseek agy codex}"
extra=("$@")

run_dir=$(cd "$run_dir" && pwd)
mkdir -p "$run_dir/results"
rm -f "$run_dir/results/status.tsv"

for s in "${seats[@]}"; do
  "$here/seat.sh" "$run_dir" "$s" "$mode" "${extra[@]}" &
done
wait

quorum=${FUSION_QUORUM:-3}
returned=0; total=0; rows=()
while IFS=$'\t' read -r ts seat m status provider model secs bytes; do
  total=$((total + 1))
  [ "$status" = "returned" ] && returned=$((returned + 1))
  rows+=("$(printf '%-9s %-22s %-34s %5ss  %s' "$seat" "$status" "${provider:-—}/${model:-—}" "$secs" "results/$seat.md")")
done <"$run_dir/results/status.tsv"

printf 'PANEL ROLL-CALL (%s, %s)\n' "$mode" "$(basename "$run_dir")"
for r in "${rows[@]}"; do printf '  %s\n' "$r"; done
printf 'QUORUM: %s/%s returned (threshold %s)\n' "$returned" "$total" "$quorum"
if [ "$returned" -lt "$quorum" ]; then
  printf 'VERDICT: DEGRADED — fewer than %s independently prompted panelists returned blocks.\n' "$quorum"
  printf 'CONVERGENCE: fallback path only; the convergence test cannot pass on a degraded panel.\n'
else
  printf 'VERDICT: real panel. Run the CONVERGENCE TEST over the blocks yourself.\n'
fi
