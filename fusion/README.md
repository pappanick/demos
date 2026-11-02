# Fusion — a local multi-model panel for Claude Code

`/fusion:fusion` runs your task past a panel of models and adjudicates the
results, instead of trusting one model alone. You are the **judge**; the panel is:

| Panelist | How it runs |
| --- | --- |
| Claude Opus (`fusion-opus-panelist`) | Claude Code subagent |
| Antigravity | `agy` CLI |
| Codex | `codex` CLI |
| Kimi (`kimi-k3.1-pro`) | `opencode run` → OpenCode Go, fallback OpenRouter `moonshotai/kimi-k3.1-pro` |
| GLM (`glm-5.3`) | `opencode run` → OpenCode Go, fallback OpenRouter `z-ai/glm-5.3` |
| Qwen (`qwen3.8-max`) | `opencode run` → OpenCode Go, fallback OpenRouter `qwen/qwen3.8-max-0902` |
| DeepSeek (`deepseek-v4.1-flash`) | `opencode run` → OpenCode Go, fallback OpenRouter `deepseek/deepseek-v4.1-flash` |

Antigravity, Codex, Kimi, GLM, Qwen, and DeepSeek are all agentic CLIs with local
file/worktree access, so they are equal members in every mode — including writing
code in isolated worktrees during parallel execution. The four opencode seats are
four distinct labs. Each runs on the OpenCode Go subscription first; when Go's
quota, rate limit, or auth fails, that seat retries once on the same model via
OpenRouter tokens, and the ledger records which provider it actually ran on.

The Claude Fable 5 seat is archived in [`archive/`](archive/README.md) and can
be restored when the subscription covers it.

## Install

```
/plugin marketplace add pappanick/demos
/plugin install fusion@demos
```

That is the whole install. It brings the skill and the Opus panelist subagent. No
files to copy, no paths to get right.

Since this repo holds several demos, you can check out only what Fusion needs:

```
/plugin marketplace add pappanick/demos --sparse .claude-plugin fusion
```

### What you get with nothing else installed

**Runs work immediately with only Claude Code — but a Claude-only panel is a
panel of one, and the protocol will say so on every run.**

A missing CLI is never fatal. The judge records it as a skip, reports the quorum
it actually ran, and proceeds. But be clear about what two seats buy you:

- The skill labels a run `DEGRADED` when fewer than three panelists return
  blocks ([`SKILL.md`](skills/fusion/SKILL.md) — "Timeouts and skips"). With only
  the Opus seat you are permanently under that threshold, so runs route to the
  fallback path rather than the evidence-grounded convergence exit.
- A Claude-only review is a one-model review — which is the thing this skill
  exists to avoid.

**Install one external CLI and the panel becomes real.** `plan:` needs two
external seats to clear the quorum threshold; `review:` wants two as well.

| Seat | Needs | Seats added |
| --- | --- | --- |
| Opus | nothing — ships with the plugin | 1 (but see above) |
| Antigravity | [`agy`](https://antigravity.google) on `PATH` | 1 |
| Codex | [`codex`](https://github.com/openai/codex) on `PATH` | 1 |
| Kimi + GLM + Qwen + DeepSeek | [opencode](https://opencode.ai), **plus** OpenCode Go and/or OpenRouter auth, **and** the fallback registration below | 4 |

### Enabling the Kimi, GLM, Qwen, and DeepSeek seats

The primaries (`opencode-go/kimi-k3.1-pro`, `opencode-go/glm-5.3`,
`opencode-go/qwen3.8-max`, `opencode-go/deepseek-v4.1-flash`) come from the
[OpenCode Go](https://opencode.ai) subscription and need no config — just
`opencode auth login` for OpenCode Go.

The OpenRouter fallbacks must be registered, because opencode rejects models not
in its config. Merge [`opencode/opencode.jsonc`](opencode/opencode.jsonc) into
your `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "openrouter": {
      "models": {
        "moonshotai/kimi-k3.1-pro":     { "name": "Kimi K3.1 Pro (OpenRouter)" },
        "z-ai/glm-5.3":                 { "name": "GLM 5.3 (OpenRouter)" },
        "qwen/qwen3.8-max-0902":        { "name": "Qwen3.8 Max 0902 (OpenRouter)" },
        "deepseek/deepseek-v4.1-flash": { "name": "DeepSeek V4.1 Flash (OpenRouter)" }
      }
    }
  }
}
```

Then check `opencode auth list` shows OpenCode Go and OpenRouter. The model IDs
are pinned for reproducibility. Falling back from Go to OpenRouter keeps the same
model; if both fail, that panelist is skipped and noted in the ledger rather than
silently swapped for a different model.

## Modes

Invoke with a prefix after `/fusion:fusion`:

- `plan:` — every panelist analyzes read-only; the judge synthesizes one plan.
- `review:` — every panelist does a strict, file/line-grounded review; the judge
  keeps the valid findings.
- `execute serial:` — one chosen writer implements, then a full review pass.
- `execute parallel:` — each writer implements in its own git worktree/branch;
  the judge diffs them and synthesizes onto the main checkout.

Each run gets `.fusion/runs/<timestamp>/` holding a `PROMPT.md` context packet,
per-panelist prompts and results, and an append-only `LEDGER.md` of structured
result blocks. Add `.fusion/` to your ignore file — run scaffolding inside the
observed tree is otherwise indistinguishable from a panelist writing to it.

## How it avoids agreeing with itself

Most of the protocol is spent preventing the panel from manufacturing a
consensus:

- **Round 1 is blind.** No panelist sees another's answer, or the ledger, or any
  judge deliberation. That is the only independent evidence sample.
- **Agreement is not corroboration.** A finding counts only where the panelist
  cites a file:line it read itself. Seven models reading one wrong sentence in the
  packet is one error with seven voices.
- **Disagreement is resolved by evidence, not by vote.** Rebuttal rounds are
  bounded, and any position change must name the file:line that forced it — an
  unexplained flip is recorded as deference and the claim stays contested.
- **A degraded panel is not a consensus.** Two seats and seven seats produce
  equally confident prose, so the judge always reports which one it ran.

## Files

```
fusion/
├── .claude-plugin/plugin.json          # plugin manifest
├── skills/fusion/SKILL.md              # the protocol (judge instructions)
├── agents/fusion-opus-panelist.md      # Claude Opus seat
├── archive/fusion-fable-panelist.md    # Claude Fable 5 seat (archived, not loaded)
└── opencode/opencode.jsonc             # OpenRouter fallback registration (opt-in)
```

## License

MIT — see [LICENSE](../LICENSE).
