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
| [`fusion/`](fusion/) | A local multi-model panel. One model judges; Claude Opus, Antigravity, Codex, Kimi, GLM, Qwen, and DeepSeek act as panelists for planning, review, and parallel execution. |

Fusion runs with nothing but Claude Code installed, though a Claude-only panel is
a degraded one by the skill's own quorum rules — install one external CLI and the
panel becomes real. See [`fusion/README.md`](fusion/README.md).

## License

MIT — see [LICENSE](LICENSE).
