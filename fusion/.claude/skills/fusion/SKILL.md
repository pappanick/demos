---
description: Run a local Fusion-style panel using Claude, Gemini, and Codex subscriptions plus OpenRouter models (Kimi, GLM) for planning, execution, and review.
disable-model-invocation: true
---

# Fusion Skill

You are the JUDGE.

The user text after `/fusion` is the task. Determine mode from the prefix:

- `plan:` read-only architecture/task planning
- `review:` read-only harsh review of current code/diff
- `execute serial:` one writer, then review
- `execute parallel:` isolated worktree branches, then synthesis

If unclear, choose `plan` for decisions and `review` for existing diffs.

## Panel Roster

- `fusion-opus-panelist` — Claude
- Gemini CLI
- Codex CLI
- Kimi — `opencode run --model openrouter/moonshotai/kimi-k2.7-code`
- GLM — `opencode run --model openrouter/z-ai/glm-5.2`

Gemini, Codex, Kimi, and GLM are the non-Claude panel — all four are agentic
CLIs with local file/worktree access. Treat them as equal members in every mode:
wherever Gemini and Codex are asked, ask Kimi and GLM the same, including as
worktree writers in Execute Parallel.

Kimi and GLM are driven through opencode (OpenRouter is the model provider; see
opencode Panelists). If opencode or its OpenRouter auth is unavailable, skip that
panelist and note the skip in the ledger — do not fail the run.

## Required Run Files

Create a fresh run directory:

`.fusion/runs/<YYYYMMDD-HHMMSS>/`

Inside it create:

- `PROMPT.md`
- `LEDGER.md`
- `results/`
- `prompts/`

Always mirror the current run's files to these stable paths so every panelist has
one canonical location, and pass the absolute run-dir path in each panelist's
prompt so it never has to guess:

- `.fusion/PROMPT.md` — copy of this run's `PROMPT.md`
- `.fusion/LEDGER.md` — copy of this run's `LEDGER.md`

## Context Packet

Before calling any panelist, write `PROMPT.md` with:

- TASK: exact user request
- MODE: plan/review/execute-serial/execute-parallel
- CONSTRAINTS: user constraints, repo instructions, package manager rules
- ACCEPTANCE: what done means
- REPO SNAPSHOT: cwd, branch, base SHA, `git status --short`
- CURRENT CHANGES: `git diff --stat` and relevant `git diff`
- RELEVANT FILES: paths plus necessary excerpts/full contents
- VALIDATION: tests/builds/checks already run and exact output
- WORKTREE PLAN: only for parallel execution
- LEDGER SO FAR: current ledger contents

Never ask a non-Claude panelist (Gemini, Codex, Kimi, GLM) to judge code from the
ledger alone. Give them the context packet, relevant files, diffs, tests,
constraints, and task.

## Ledger Block Format

Append blocks only. Do not edit prior blocks.

---
PANELIST: <name>
TIME: <ISO8601>
MODE: <plan|review|execute-serial|execute-parallel>
BRANCH: <branch or none>
WORKTREE: <path or none>
CONCLUSION: <one paragraph>
CHANGES: <files touched, one line each | none>
TESTS: <commands and results | not run>
FINDINGS: <review findings | none>
OPEN: <questions for judge | none>
---

## Caching Rules

- Use `fusion-opus-panelist` for Claude panel work; do not create one-off panelists.
- Prefer resuming the same panelist during a follow-up in the same session when useful.
- Keep the static protocol stable and put volatile task data in `PROMPT.md`.
- Use project memory for durable repo facts only.
- Prefer forks when a Claude worker needs parent context and prompt-cache reuse.
- Prefer worktrees when independent implementation attempts matter more than cache reuse.
- Do not change model/effort mid-run unless the user asks.

## Read-Only Enforcement

"Do not edit files" in plan/review is an instruction, not a guard — Gemini,
Codex, Kimi, and GLM are agentic CLIs that *can* write. Review mode runs against a
dirty tree, so a careless revert would destroy the user's uncommitted work.
Prevent writes; never "clean up" after them.

1. Run each external panelist in its CLI's hard read-only mode:
   - opencode (Kimi/GLM): `opencode run --agent plan …` — the `plan` agent cannot
     edit files or run mutating commands.
   - Codex: `codex exec --sandbox read-only …`.
   - Gemini: `gemini --approval-mode plan …` (`plan` = read-only).
   - Any CLI with no hard read-only mode: create a disposable worktree off HEAD
     at the fixed path `.fusion/worktrees/<run>/<panelist>-readonly`, run the
     panelist with that worktree as its cwd, and read its result. Before removal,
     verify the resolved path is inside `.fusion/worktrees/`, then remove that
     exact path: `git worktree remove --force .fusion/worktrees/<run>/<panelist>-readonly`.
     Never pass a placeholder, empty, or unverified computed path to
     `git worktree remove`. The user's checkout is never exposed.
2. Tripwire, not cleanup: capture `git status --porcelain` before and after each
   panelist that touched the real checkout. If it differs, STOP and do not edit
   the tree at all — record a `READ-ONLY VIOLATION` in that panelist's ledger
   block, discard that panelist's output, and ask the user how to proceed. Never
   run `git checkout -- .`, mass-delete untracked files, or auto-undo "stray"
   paths: a long panel run can race with files the user created, so an automated
   undo can destroy real work. Leave the tree as found and let the user decide.

## Modes

### Plan

All panelists are read-only — enforce per Read-Only Enforcement.

1. Build `PROMPT.md`.
2. Ask `fusion-opus-panelist` to analyze and return one result block.
3. Ask Gemini, Codex, Kimi, and GLM to analyze `PROMPT.md`; require one result
   block each; no edits. Gemini and Codex via their CLIs, Kimi and GLM via
   opencode.
4. Append all blocks to `LEDGER.md`.
5. Synthesize one plan: agreements, disagreements, chosen path, risks, validation.

### Review

All panelists are read-only — enforce per Read-Only Enforcement.

1. Build `PROMPT.md` with current diff, files, tests, and constraints.
2. Ask `fusion-opus-panelist` for strict review.
3. Ask Gemini, Codex, Kimi, and GLM for strict review: findings first, severity
   ordered, file/line grounded. Gemini and Codex via their CLIs, Kimi and GLM
   via opencode.
4. Append all blocks.
5. Judge decides which findings are valid.
6. If fixes are needed, apply them serially in the main checkout.
7. Re-run relevant validation.

### Execute Serial

Only one writer.

1. Choose WRITER: any one panelist — judge, `fusion-opus-panelist`, Gemini,
   Codex, Kimi, or GLM. One writer only. A non-Claude writer runs in the main
   checkout via its CLI (Kimi/GLM: `opencode run` without `--dir`).
2. Build `PROMPT.md`.
3. Writer implements the smallest correct change.
4. Run validation.
5. Rebuild `PROMPT.md` with the actual diff and test output.
6. Run Review mode.
7. Judge applies accepted amendments serially.
8. Run final validation.

### Execute Parallel

Use separate worktrees and branches.

1. Capture `BASE_SHA=$(git rev-parse HEAD)`.
2. Create branches/worktrees from the same base:
   - `fusion/<run>/opus`
   - `fusion/<run>/gemini`
   - `fusion/<run>/codex`
   - `fusion/<run>/kimi`
   - `fusion/<run>/glm`
3. Each worker edits only its own worktree, but writes its result block to the
   MAIN run dir by absolute path — never to a `.fusion/` inside the worktree.
   Kimi and GLM run as (message first, `--file` last, absolute paths):
   `opencode run "Implement only in this worktree. Return exactly one Fusion result block." --dir <worktree> --model openrouter/<id> --file=<run-dir>/prompts/<name>.md > <run-dir>/results/<name>.md`
4. Each worker's result block (in `<run-dir>/results/<name>.md`) records:
   - branch
   - worktree path
   - changed files
   - tests run
   - patch summary
   The judge then appends every `results/<name>.md` to the central `LEDGER.md`;
   workers never write the central ledger directly.
5. Judge compares:
   - `git diff <base>...fusion/<run>/opus`
   - `git diff <base>...fusion/<run>/gemini`
   - `git diff <base>...fusion/<run>/codex`
   - `git diff <base>...fusion/<run>/kimi`
   - `git diff <base>...fusion/<run>/glm`
6. Judge synthesizes the best final implementation on the main checkout.
7. Run Review mode against the integrated diff.
8. Apply accepted amendments serially.
9. Run final validation.

## External CLI Calls

Prefer prompt files over interpolating raw user text into shell commands.

For Gemini, Codex, Kimi, and GLM:
- create `prompts/gemini.md`, `prompts/codex.md`, `prompts/kimi.md`, `prompts/glm.md`
- include `PROMPT.md` plus latest `LEDGER.md`
- require exactly one Fusion result block
- in plan/review, explicitly say: `Do not edit files.`

If the local CLI supports prompt files or stdin, use that. opencode reads the
packet via `--file=<path>` with a short message positional first (see opencode
Panelists). Only fall back to `"$(cat prompt-file)"` when a CLI has no file/stdin
input; even then the prompt is read as file data, not spliced raw into the shell.

## opencode Panelists

Kimi and GLM are agentic CLIs driven through opencode, with OpenRouter as the
model provider. They are full panelists in every mode, equal to Gemini and Codex.

Models (registered in `~/.config/opencode/opencode.jsonc` under
`provider.openrouter.models`):

- Kimi: `openrouter/moonshotai/kimi-k2.7-code`
- GLM: `openrouter/z-ai/glm-5.2`

These IDs are pinned for reproducibility. If one no longer resolves, skip that
panelist and note it in the ledger — do not silently swap to a different model
without the user's explicit approval. `opencode models | grep openrouter` lists
what is registered; `curl -s https://openrouter.ai/api/v1/models` lists what
exists; opencode rejects models not in config, so a newly approved id must be
registered in `~/.config/opencode/opencode.jsonc` first.

Auth: OpenRouter must be logged in (`opencode auth list` shows it). If opencode or
its OpenRouter auth is missing, skip that panelist and note it; do not fail the run.

Invocation — attach the packet with `--file=` (prompt read as file data, not
spliced into the shell). The message positional MUST come before `--file`, which
is array-typed and otherwise swallows the message. Use absolute paths for prompt
and output so `--dir` worktrees still resolve the main run dir. `<run-dir>` is the
main `.fusion/runs/<ts>/`:

```sh
# read-only (plan/review) — `--agent plan` is a hard guard (cannot edit files)
opencode run "Read the attached prompt. Return exactly one Fusion result block." \
  --agent plan --model openrouter/moonshotai/kimi-k2.7-code \
  --file=<run-dir>/prompts/kimi.md > <run-dir>/results/kimi.md

# Execute Parallel writer — edits its own worktree, result to the MAIN run dir
opencode run "Read the attached prompt. Implement only in this worktree. Return exactly one Fusion result block." \
  --dir <worktree> --model openrouter/z-ai/glm-5.2 \
  --file=<run-dir>/prompts/glm.md > <run-dir>/results/glm.md
```

Swap model, prompt file, and output path per panelist. If opencode prints a
`ProviderModelNotFoundError` or other error instead of a result block, record a
skipped panelist; do not invent a block.

## Judge Output

Final answer must include:

- decision or implemented result
- meaningful disagreements and adjudication
- files changed, if any
- validation run, if any
- remaining risks or open questions

Drop unsupported claims. Do not majority-vote blindly.
