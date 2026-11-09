#!/usr/bin/env bash
# Install demos skills into local agent harnesses (pi, codex, ...).
#
# A demo is authored once per harness. The layout convention is:
#
#   <plugin>/skills/<skill>/SKILL.md        Claude Code plugin (installed via /plugin)
#   <plugin>/<harness>/skills/<skill>/      any other harness; this script links it
#
# Example:
#   fusion/skills/fusion/                   -> Claude Code (plugin marketplace)
#   fusion/pi/skills/fusion/                -> $PI_CODING_AGENT_DIR/skills/fusion
#   fusion/codex/skills/fusion/             -> $CODEX_HOME/skills/fusion
#
# Usage:
#   ./install.sh                      link every harness skill found
#   ./install.sh --harness pi         only one harness (repeatable)
#   ./install.sh --copy               copy instead of symlink (host w/o this clone)
#   ./install.sh --force              replace a real directory in the way
#   ./install.sh --uninstall          remove the links this script owns
#   ./install.sh --list               print what would be installed
#   ./install.sh --dry-run            show actions without doing them
#   ./install.sh --quiet              only report errors (for cron)
#
# Environment:
#   DEMOS_REPO      repo root (default: directory containing this script)
#   PI_CODING_AGENT_DIR   pi config dir (default: ~/.pi/agent)
#   CODEX_HOME      codex config dir (default: ~/.codex)
#
# Nothing outside this repo and the target harness skill dirs is touched.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${DEMOS_REPO:=$repo}"

mode=link
force=0
dry=0
quiet=0
uninstall=0
list=0
harnesses=()

say() { [ "$quiet" -eq 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case $1 in
    --harness)    [ $# -ge 2 ] || die "--harness needs a value"; harnesses+=("$2"); shift 2 ;;
    --harness=*)  harnesses+=("${1#*=}"); shift ;;
    --copy)       mode=copy; shift ;;
    --force)      force=1; shift ;;
    --uninstall)  uninstall=1; shift ;;
    --list)       list=1; shift ;;
    --dry-run)    dry=1; shift ;;
    --quiet|-q)   quiet=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1 (try --help)" ;;
  esac
done

# Harness name -> skills directory. Claude Code is deliberately absent: its
# plugins are installed by the marketplace, not by copying files into ~/.claude.
skills_dir_for() {
  case $1 in
    pi)    printf '%s/skills\n' "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" ;;
    codex) printf '%s/skills\n' "${CODEX_HOME:-$HOME/.codex}" ;;
    *)     return 1 ;;
  esac
}

harness_wanted() {
  [ ${#harnesses[@]} -eq 0 ] && return 0
  local h
  for h in "${harnesses[@]}"; do
    [ "$h" = "$1" ] && return 0
  done
  return 1
}

# --- discover skills ---------------------------------------------------------
# Matches <plugin>/<harness>/skills/<skill>/SKILL.md
shopt -s nullglob
srcs=("$DEMOS_REPO"/*/*/skills/*/SKILL.md)
shopt -u nullglob

[ ${#srcs[@]} -eq 0 ] && die "no <plugin>/<harness>/skills/<skill>/SKILL.md under $DEMOS_REPO"

found=0
for manifest in "${srcs[@]}"; do
  src=${manifest%/SKILL.md}
  skill=${src##*/}
  rest=${src%/skills/"$skill"}      # <repo>/<plugin>/<harness>
  harness=${rest##*/}
  plugin=${rest%/"$harness"}
  plugin=${plugin##*/}

  if ! target_dir=$(skills_dir_for "$harness"); then
    warn "skip $plugin/$harness/$skill: unknown harness '$harness'"
    continue
  fi
  harness_wanted "$harness" || continue
  found=1

  target=$target_dir/$skill

  if [ "$list" -eq 1 ]; then
    printf '%s/%s\t%s\t%s -> %s\n' "$plugin" "$harness" "$skill" "$src" "$target"
    continue
  fi

  if [ "$uninstall" -eq 1 ]; then
    if [ -L "$target" ] && [ "$(readlink -f "$target" 2>/dev/null || readlink "$target")" = "$(readlink -f "$src")" ]; then
      [ "$dry" -eq 1 ] && { say "would remove $target"; continue; }
      rm -f "$target" && say "unlinked $target"
    elif [ -e "$target" ]; then
      say "left $target alone (not a link to $src)"
    fi
    continue
  fi

  if [ "$dry" -eq 1 ]; then
    say "would $mode $src -> $target"
    continue
  fi

  mkdir -p "$target_dir" || { warn "cannot create $target_dir"; continue; }

  # Already correct link?
  if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$src")" ]; then
    say "ok $target"
    continue
  fi

  # Something in the way.
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ]; then
      rm -f "$target" || { warn "cannot replace $target"; continue; }
    elif [ "$force" -eq 1 ]; then
      rm -rf "$target" || { warn "cannot remove $target"; continue; }
    else
      warn "skip $target: exists and is not a link (re-run with --force to replace)"
      continue
    fi
  fi

  if [ "$mode" = copy ]; then
    cp -R "$src" "$target" && say "copied $target"
  else
    ln -s "$src" "$target" && say "linked $target"
  fi
done

[ "$found" -eq 0 ] && die "no skills matched the requested harnesses (${harnesses[*]:-none given})"

exit 0
