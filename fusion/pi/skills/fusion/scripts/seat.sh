#!/usr/bin/env bash
# Run one Fusion panelist seat and record its block, stderr, and provider attribution.
#
# Usage:
#   seat.sh <run-dir> <seat> <plan|review|write> [options]
#
# Seats: kimi glm qwen deepseek agy codex
# Options:
#   --cwd DIR        run the seat in DIR (writer worktrees). Default: $PWD
#   --paste FILE     append FILE verbatim to the seat prompt (rebuttal rounds). Repeatable.
#   --round K        rebuttal round number (writes prompts/<seat>.r<K>.md and results/round-0K/<seat>.md)
#   --prompt FILE    use FILE as the whole prompt instead of _shared.md + PROMPT.md
#   --timeout SECS   wall-clock cap (default 300)
#   --tag NAME       status/result label (default: seat name; use for duplicates like agy2)
#
# Env overrides: FUSION_AGY_MODEL, FUSION_CODEX_MODEL, FUSION_TIMEOUT
#
# Output (under <run-dir>): prompts/<seat>.md, results/<seat>.md, results/<seat>.err,
# results/<seat>.jsonl (pi seats), results/status.tsv (append-only).
# Exit 0 always; read results/status.tsv for the verdict.
set -uo pipefail

run_dir=${1:?usage: seat.sh <run-dir> <seat> <plan|review|write> [options]}
seat=${2:?missing seat}
mode=${3:?missing mode (plan|review|write)}
shift 3

cwd=$PWD
round=""
prompt_file=""
tag=$seat
timeout_s=${FUSION_TIMEOUT:-}
pastes=()

while [ $# -gt 0 ]; do
  case $1 in
    --cwd) cwd=$2; shift 2 ;;
    --paste) pastes+=("$2"); shift 2 ;;
    --round) round=$2; shift 2 ;;
    --prompt) prompt_file=$2; shift 2 ;;
    --timeout) timeout_s=$2; shift 2 ;;
    --tag) tag=$2; shift 2 ;;
    *) echo "seat.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

# Per-seat default caps: codex is the slowest seat (observed ~190s on a trivial prompt).
if [ -z "$timeout_s" ]; then
  case $seat in codex) timeout_s=600 ;; *) timeout_s=300 ;; esac
fi

run_dir=$(cd "$run_dir" && pwd)
mkdir -p "$run_dir/prompts" "$run_dir/results"
out_dir=$run_dir/results
[ -n "$round" ] && out_dir=$run_dir/results/round-0$round
mkdir -p "$out_dir"

suffix=""
[ -n "$round" ] && suffix=".r$round"
prompt_path=$run_dir/prompts/$tag$suffix.md
block_path=$out_dir/$tag.md
err_path=$out_dir/$tag.err
jsonl_path=$out_dir/$tag.jsonl
: >"$block_path"; : >"$err_path"

# ---------- compose the seat prompt ----------
if [ -n "$prompt_file" ]; then
  cp "$prompt_file" "$prompt_path"
else
  : >"$prompt_path"
  [ -f "$run_dir/prompts/_shared.md" ] && cat "$run_dir/prompts/_shared.md" >>"$prompt_path"
  cat "$run_dir/PROMPT.md" >>"$prompt_path"
  for p in "${pastes[@]:-}"; do
    [ -n "$p" ] || continue
    printf '\n\n===== %s =====\n' "$(basename "$p")" >>"$prompt_path"
    cat "$p" >>"$prompt_path"
  done
fi

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
start=$(date +%s)
status=""; provider=""; model=""

record() { # status provider model block_bytes
  local secs=$(( $(date +%s) - start ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(stamp)" "$tag" "$mode" "$1" "${2:--}" "${3:--}" "$secs" "${4:--}" >>"$run_dir/results/status.tsv"
  printf 'SEAT: %s\nSTATUS: %s\nPROVIDER: %s\nMODEL: %s\nSECONDS: %s\nBLOCK: %s\n' \
    "$tag" "$1" "${2:--}" "${3:--}" "$secs" "${block_path#$run_dir/}"
}

have_block() { grep -q '^PANELIST:' "$block_path" 2>/dev/null; }

# ---------- opencode-go seats, run through pi ----------
go_id=""; or_id=""
case $seat in
  kimi)     go_id=kimi-k3.1-pro;     or_id=moonshotai/kimi-k3.1-pro ;;
  glm)      go_id=glm-5.3;           or_id=z-ai/glm-5.3 ;;
  qwen)     go_id=qwen3.8-max;       or_id=qwen/qwen3.8-max-prime ;;
  deepseek) go_id=deepseek-v4.1-flash; or_id=deepseek/deepseek-v4.1-flash ;;
esac

run_pi() { # model out_marker
  local m=$1
  local ro=()
  [ "$mode" != "write" ] && ro=(--tools read,grep,find,ls)
  ( cd "$cwd" && timeout "$timeout_s" pi --mode json -p --no-session \
      --model "$m" "${ro[@]}" \
      --append-system-prompt "You are one panelist in a Fusion panel. Return exactly one FUSION RESULT BLOCK in the format the prompt requires; never act as the judge." \
      "$(cat "$prompt_path")" ) >"$jsonl_path" 2>>"$err_path"
}

pi_provider() { jq -r 'select(.type=="message_end" and .message.role=="assistant") | .message.provider // empty' "$jsonl_path" 2>/dev/null | tail -1; }
pi_model()    { jq -r 'select(.type=="message_end" and .message.role=="assistant") | .message.model // empty' "$jsonl_path" 2>/dev/null | tail -1; }
pi_text()     { jq -rs '[.[] | select(.type=="message_end" and .message.role=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // ""' "$jsonl_path" 2>/dev/null; }

if [ -n "$go_id" ]; then
  run_pi "opencode-go/$go_id"
  rc=$?
  provider=$(pi_provider); model=$(pi_model); pi_text >"$block_path"

  if [ $rc -ne 0 ] || ! have_block; then
    # one fallback attempt on the same model family via OpenRouter
    cp "$err_path" "$run_dir/results/$tag.go.err" 2>/dev/null
    : >"$err_path"
    run_pi "openrouter/$or_id"
    rc=$?
    provider=$(pi_provider); model=$(pi_model); pi_text >"$block_path"
  fi
  # The opencode-go-fallback extension can reroute internally on a Go limit too,
  # so attribute by the provider that actually answered, not by what we asked for.
  if [ "$provider" = "openrouter" ] && have_block; then
    provider="openrouter(fallback)"
  fi

  if [ $rc -eq 124 ]; then status="SKIPPED (TIMEOUT)"
  elif have_block; then status="returned"
  elif [ $rc -ne 0 ]; then status="SKIPPED (exit $rc)"
  else status="SKIPPED (no block)"; fi
  record "$status" "$provider" "$model" "$(wc -c <"$block_path")"
  [ "$status" = "returned" ] && exit 0 || exit 1
fi

# ---------- agy (Antigravity / Gemini) ----------
if [ "$seat" = "agy" ]; then
  agy_model=${FUSION_AGY_MODEL:-Gemini 4 Argon (High)}
  # Read-only modes: headless agy auto-denies tools, so the prompt must be self-contained.
  if [ "$mode" != "write" ]; then
    { printf 'Everything you need is inlined below. Do NOT use any tools: no shell commands, no file reads, no web fetches. Answer from the packet only; where you cannot verify a claim without a tool, say so.\n\n'
      cat "$prompt_path"; } >"$prompt_path.tmp" && mv "$prompt_path.tmp" "$prompt_path"
    ( cd "$cwd" && timeout "$timeout_s" agy -p "$(cat "$prompt_path")" \
        --model "$agy_model" --mode plan --sandbox --disable-slash-commands < /dev/null ) \
        >"$block_path" 2>>"$err_path"
  else
    ( cd "$cwd" && timeout "$timeout_s" agy -p "$(cat "$prompt_path")" \
        --model "$agy_model" --mode accept-edits --sandbox --disable-slash-commands < /dev/null ) \
        >"$block_path" 2>>"$err_path"
  fi
  rc=$?
  provider="antigravity"; model=$agy_model

  if [ $rc -eq 124 ]; then status="SKIPPED (TIMEOUT)"
  elif have_block; then status="returned"
  elif [ $rc -ne 0 ]; then status="SKIPPED (exit $rc)"
  elif grep -qi 'no output produced' "$err_path" "$block_path"; then status="SKIPPED (no tool access)"
  else status="SKIPPED (no block)"; fi
  record "$status" "$provider" "$model" "$(wc -c <"$block_path")"
  [ "$status" = "returned" ] && exit 0 || exit 1
fi

# ---------- codex (ChatGPT subscription) ----------
if [ "$seat" = "codex" ]; then
  codex_model=${FUSION_CODEX_MODEL:-gpt-5.6-sol}
  sandbox=read-only
  [ "$mode" = "write" ] && sandbox=workspace-write
  ( cd "$cwd" && timeout "$timeout_s" codex exec -m "$codex_model" -s "$sandbox" \
      --skip-git-repo-check --ephemeral - < "$prompt_path" ) >"$block_path" 2>>"$err_path"
  rc=$?
  provider="codex"; model=$codex_model

  if [ $rc -eq 124 ]; then status="SKIPPED (TIMEOUT)"
  elif have_block; then status="returned"
  elif [ $rc -ne 0 ]; then status="SKIPPED (exit $rc)"
  else status="SKIPPED (no block)"; fi
  record "$status" "$provider" "$model" "$(wc -c <"$block_path")"
  [ "$status" = "returned" ] && exit 0 || exit 1
fi

echo "seat.sh: unknown seat '$seat' (use kimi|glm|qwen|deepseek|agy|codex)" >&2
exit 2
