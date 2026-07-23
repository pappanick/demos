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

**Install gives you a working panel — both Claude seats, out of the box. Every
extra CLI you have installed adds a seat.**

A missing CLI is never fatal. The judge records it as a skip in the ledger,
reports the quorum it actually ran, and proceeds. What a plugin cannot do is
install other people's binaries or write their config, so the remaining seats are
opt-in:

| Seat | Needs |
| --- | --- |
| Opus, Fable | nothing — ships with the plugin |
| Antigravity | [`agy`](https://antigravity.google) on `PATH` |
| Codex | [`codex`](https://github.com/openai/codex) on `PATH` |
| Kimi, GLM | [opencode](https://opencode.ai) + OpenRouter auth + the model registration below |

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
