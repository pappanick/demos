# Fusion — a local multi-model panel for Claude Code

`/fusion:fusion` runs your task past a panel of models and adjudicates the
results, instead of trusting one model alone. You are the **judge**; the panel is:

| Panelist | How it runs |
| --- | --- |
| Claude Opus (`fusion-opus-panelist`) | Claude Code subagent |
| Claude Fable 5 (`fusion-fable-panelist`) | Claude Code subagent |
| Antigravity | `agy` CLI |
| Codex | `codex` CLI |
| Kimi (`moonshotai/kimi-k3`) | `opencode run` → OpenRouter |
| GLM (`z-ai/glm-5.2`) | `opencode run` → OpenRouter |

Antigravity, Codex, Kimi, and GLM are all agentic CLIs with local file/worktree
access, so they are equal members in every mode — including writing code in
isolated worktrees during parallel execution.

The two Claude seats are deliberately different models. They are also the one
pair whose errors correlate, so the protocol does not count their agreement as
two independent votes.

## Install

```
/plugin marketplace add pappanick/demos
/plugin install fusion@demos
```

That is the whole install. It brings the skill and both panelist subagents. No
files to copy, no paths to get right.

Since this repo holds several demos, you can check out only what Fusion needs:

```
/plugin marketplace add pappanick/demos --sparse .claude-plugin fusion
```

### What you get with nothing else installed

**Runs work immediately with only Claude Code — but a Claude-only panel is a
degraded panel, and the protocol will say so on every run.**

A missing CLI is never fatal. The judge records it as a skip, reports the quorum
it actually ran, and proceeds. But be clear about what two seats buy you:

- The skill labels a run `DEGRADED` when fewer than three panelists return
  blocks ([`SKILL.md`](skills/fusion/SKILL.md) — "Timeouts and skips"). With only
  the Claude seats you are permanently under that threshold, so runs route to the
  fallback path rather than the evidence-grounded convergence exit.
- `review:` mode seats **only** `fusion-opus-panelist` (see Modes → Review). Fable
  is not in the review workflow, so a Claude-only review is a one-model review —
  which is the thing this skill exists to avoid.
- The two Claude seats are the one pair whose errors correlate, and the protocol
  deliberately discounts their agreement rather than counting it as two votes.

**Install one external CLI and the panel becomes real.** Any single one of them
clears the quorum threshold for `plan:`; `review:` wants two.

| Seat | Needs | Seats added |
| --- | --- | --- |
| Opus, Fable | nothing — ships with the plugin | 2 (but see above) |
| Antigravity | [`agy`](https://antigravity.google) on `PATH` | 1 |
| Codex | [`codex`](https://github.com/openai/codex) on `PATH` | 1 |
| Kimi + GLM | [opencode](https://opencode.ai), **plus** OpenRouter auth **and** the model registration below — the binary alone is not enough | 2 |

### Enabling the Kimi and GLM seats

opencode rejects any model that is not registered in its config, so merge
[`opencode/opencode.jsonc`](opencode/opencode.jsonc) into your
`~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "openrouter": {
      "models": {
        "moonshotai/kimi-k3": { "name": "Kimi K3 (OpenRouter)" },
        "z-ai/glm-5.2":       { "name": "GLM 5.2 (OpenRouter)" }
      }
    }
  }
}
```

Then check `opencode auth list` shows OpenRouter. The model IDs are pinned for
reproducibility — if one stops resolving, that panelist is skipped and noted in
the ledger rather than silently swapped for a substitute.

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
  cites a file:line it read itself. Six models reading one wrong sentence in the
  packet is one error with six voices.
- **Disagreement is resolved by evidence, not by vote.** Rebuttal rounds are
  bounded, and any position change must name the file:line that forced it — an
  unexplained flip is recorded as deference and the claim stays contested.
- **A degraded panel is not a consensus.** Two seats and six seats produce
  equally confident prose, so the judge always reports which one it ran.

## Files

```
fusion/
├── .claude-plugin/plugin.json          # plugin manifest
├── skills/fusion/SKILL.md              # the protocol (judge instructions)
├── agents/fusion-opus-panelist.md      # Claude Opus seat
├── agents/fusion-fable-panelist.md     # Claude Fable 5 seat
└── opencode/opencode.jsonc             # OpenRouter model registration (opt-in)
```

## License

MIT — see [LICENSE](../LICENSE).
