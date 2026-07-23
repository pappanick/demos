# demos

Small, self-contained demos for Claude Code, distributed as plugins. An AI panel
beats solo players — inspired by OpenRouter Fusion.

## Install

This repo is a Claude Code plugin marketplace. Add it once:

```
/plugin marketplace add pappanick/demos
```

Then install whichever demo you want:

```
/plugin install fusion@demos
```

## Contents

| Plugin | What it does |
| --- | --- |
| [`fusion/`](fusion/) | A local multi-model panel. One model judges; Claude Opus, Claude Fable, Antigravity, Codex, Kimi, and GLM act as panelists for planning, review, and parallel execution. |

Fusion works with nothing but Claude Code installed — you get both Claude seats
out of the box, and each additional CLI on your `PATH` adds a seat. See
[`fusion/README.md`](fusion/README.md).

## License

MIT — see [LICENSE](LICENSE).
