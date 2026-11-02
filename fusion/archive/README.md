# Archived seats

Files here are NOT loaded by the plugin — Claude Code only discovers agents
under `fusion/agents/`. They are kept so a seat can be restored without
rewriting it.

## `fusion-fable-panelist.md` — Claude Fable 5

Retired from the roster until the subscription includes Fable. To restore:

1. `git mv fusion/archive/fusion-fable-panelist.md fusion/agents/`
2. In `skills/fusion/SKILL.md`, add the seat back to the Panel Roster, the
   Provider correlation note (Opus + Fable are one provider — their agreement is
   not two votes), the Parity invariant, Plan step 2 (`results/fable.md`), and
   the Execute Parallel branch list (`fusion/<run>/fable`).
3. Add it to the seat tables in `README.md`.
4. Add `"fusion-fable-panelist"` back to `REQUIRED_AGENTS` in
   `scripts/check-consistency.py`.
