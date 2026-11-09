# demos

Small, self-contained demos for coding agents. An AI panel beats solo players —
inspired by OpenRouter Fusion.

Each demo is authored once per harness. Claude Code consumes this repo as a plugin
marketplace; every other harness gets its skill through `install.sh`.

## Install

### Claude Code

This repo is a Claude Code plugin marketplace. Add it once:

```
/plugin marketplace add pappanick/demos
```

Then install whichever demo you want:

```
/plugin install fusion@demos
```

### pi (and Codex, once the variant lands)

```
git clone git@github.com:pappanick/demos.git ~/demos
~/demos/install.sh              # link every harness skill for this machine
```

The installer links `fusion/pi/skills/fusion` into
`$PI_CODING_AGENT_DIR/skills` (default `~/.pi/agent/skills`) and, for harnesses
that ship a variant, the matching directory elsewhere. It is idempotent, so
after a `git pull` re-running it is enough. Useful flags:

```
./install.sh --list            # show skill -> target mapping
./install.sh --harness pi      # only one harness
./install.sh --copy            # copy instead of symlink (host without this clone)
./install.sh --force           # replace a real directory in the way
./install.sh --uninstall       # remove the links this script owns
```

Claude Code is intentionally absent from the installer: its plugins are managed
by the marketplace, not by copying files into `~/.claude`.

If you already keep a dotfiles repo, add this to its sync hook so every machine
stays current:

```sh
git -C "$HOME/demos" pull --ff-only -q 2>/dev/null || git clone -q git@github.com:pappanick/demos.git "$HOME/demos"
"$HOME/demos/install.sh" --quiet
```

## Contents

| Plugin | Harnesses | What it does |
| --- | --- | --- |
| [`fusion/`](fusion/) | Claude Code, pi | A local multi-model panel. One model judges; Claude Opus, Antigravity, Codex, Kimi, GLM, Qwen, and DeepSeek act as panelists for planning, review, and parallel execution. |

Fusion runs with nothing but the host harness installed, though a single-model
panel is a degraded one by the skill's own quorum rules — install one external CLI
and the panel becomes real. See [`fusion/README.md`](fusion/README.md).

## Layout

```
<plugin>/skills/<skill>/SKILL.md          # Claude Code plugin skill (auto-discovered)
<plugin>/<harness>/skills/<skill>/        # another harness's variant, linked by install.sh
```

A harness variant exists only where the driving differs in substance: the pi port
runs panelists through `pi` headless seats and `scripts/seat.sh`, which Claude Code
does with subagents. The protocol itself (roster, run files, convergence test) is
kept in step by `scripts/check-consistency.py`, which CI runs on every push.

## License

MIT — see [LICENSE](LICENSE).

