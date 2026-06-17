# Fusion — a local multi-model panel for Claude Code

`/fusion` runs your task past a panel of models and adjudicates the results,
instead of trusting one model alone. You are the **judge**; the panel is:

| Panelist | How it runs |
| --- | --- |
| Claude (`fusion-opus-panelist`) | Claude Code subagent |
| Gemini | Gemini CLI |
| Codex | Codex CLI |
| Kimi (`moonshotai/kimi-k2.7-code`) | `opencode run` → OpenRouter |
| GLM (`z-ai/glm-5.2`) | `opencode run` → OpenRouter |

Gemini, Codex, Kimi, and GLM are all agentic CLIs with local file/worktree
access, so they are equal members in every mode — including writing code in
isolated worktrees during parallel execution.

## Modes

Invoke with a prefix after `/fusion`:

- `plan:` — every panelist analyzes read-only; the judge synthesizes one plan.
- `review:` — every panelist does a strict, file/line-grounded review; the judge
  keeps the valid findings and fixes them serially.
- `execute serial:` — one chosen writer implements, then a full review pass.
- `execute parallel:` — each panelist implements in its own git worktree/branch;
  the judge diffs all of them and synthesizes the best result on `main`.

Each run gets `.fusion/runs/<timestamp>/` with a `PROMPT.md` context packet and an
append-only `LEDGER.md` of structured result blocks. Plan/review are held
read-only by a hard guard (opencode's `--agent plan`, per-CLI sandboxes, and a
`git status` before/after snapshot that reverts and ledger-notes any stray edit).

## Install

Copy the skill and panelist agent into your Claude Code config:

```sh
cp -r fusion/.claude/skills/fusion   ~/.claude/skills/
cp    fusion/.claude/agents/fusion-opus-panelist.md ~/.claude/agents/
```

Register the OpenRouter models so opencode will accept them (opencode rejects
models not in config). Merge `fusion/opencode/opencode.jsonc` into your
`~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "openrouter": {
      "models": {
        "moonshotai/kimi-k2.7-code": { "name": "Kimi K2.7 Code (OpenRouter)" },
        "z-ai/glm-5.2":             { "name": "GLM 5.2 (OpenRouter)" }
      }
    }
  }
}
```

## Requirements

- Claude Code (the `/fusion` skill + `fusion-opus-panelist` agent).
- [opencode](https://opencode.ai) with OpenRouter logged in (`opencode auth list`
  should show OpenRouter). This is what drives Kimi and GLM.
- Optional but recommended: the Gemini and Codex CLIs for the full five-model panel.

The OpenRouter model IDs are pinned for reproducibility. If one stops resolving,
that panelist is skipped and noted in the ledger rather than silently swapped.

## Files

```
fusion/
├── .claude/
│   ├── skills/fusion/SKILL.md          # the /fusion protocol (judge instructions)
│   └── agents/fusion-opus-panelist.md  # the Claude panelist subagent
└── opencode/opencode.jsonc             # OpenRouter model registration
```
