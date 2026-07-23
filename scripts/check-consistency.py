#!/usr/bin/env python3
"""Assert the published Fusion plugin is internally consistent.

The failure this exists to prevent actually happened: the repo shipped an
opencode config registering `moonshotai/kimi-k2.7-code` while the skill invoked
`moonshotai/kimi-k3`, so anyone who installed it got a ProviderModelNotFoundError
on two of six seats. Model IDs live in three files and drift silently.

Run: python3 scripts/check-consistency.py
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARKETPLACE = ROOT / ".claude-plugin" / "marketplace.json"
PLUGIN = ROOT / "fusion" / ".claude-plugin" / "plugin.json"
SKILL = ROOT / "fusion" / "skills" / "fusion" / "SKILL.md"
OPENCODE = ROOT / "fusion" / "opencode" / "opencode.jsonc"
PLUGIN_README = ROOT / "fusion" / "README.md"

# `openrouter/vendor/model` — the generic placeholder `openrouter/<id>` has no
# inner slash and so is correctly ignored.
MODEL_RE = re.compile(r"openrouter/([\w.-]+/[\w.-]+)")

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def strip_jsonc(text):
    """Drop //-comments so a .jsonc file can be parsed as JSON."""
    return re.sub(r"^\s*//.*$", "", text, flags=re.MULTILINE)


def main():
    for path in (MARKETPLACE, PLUGIN, SKILL, OPENCODE, PLUGIN_README):
        check(path.exists(), f"missing required file: {path.relative_to(ROOT)}")
    if failures:
        return report()

    marketplace = json.loads(MARKETPLACE.read_text())
    plugin = json.loads(PLUGIN.read_text())
    opencode = json.loads(strip_jsonc(OPENCODE.read_text()))
    skill_text = SKILL.read_text()
    readme_text = PLUGIN_README.read_text()

    # --- manifests agree with each other and with the tree ---
    entries = {p["name"]: p for p in marketplace.get("plugins", [])}
    check(
        plugin["name"] in entries,
        f"plugin.json name {plugin['name']!r} is not listed in marketplace.json "
        f"(listed: {sorted(entries)})",
    )
    if plugin["name"] in entries:
        source = entries[plugin["name"]]["source"]
        check(
            (ROOT / source).is_dir(),
            f"marketplace.json source {source!r} is not a directory",
        )

    # --- conventional component dirs are where Claude Code looks for them ---
    plugin_dir = ROOT / "fusion"
    check(
        (plugin_dir / "skills" / "fusion" / "SKILL.md").exists(),
        "skill must live at fusion/skills/fusion/SKILL.md for auto-discovery",
    )
    for agent in ("fusion-opus-panelist", "fusion-fable-panelist"):
        check(
            (plugin_dir / "agents" / f"{agent}.md").exists(),
            f"missing agent fusion/agents/{agent}.md — the skill's Panel Roster "
            f"names it, so shipping without it yields a seat that cannot start",
        )

    # --- every model the skill invokes is registered and documented ---
    skill_models = set(MODEL_RE.findall(skill_text))
    check(skill_models, "no openrouter model IDs found in SKILL.md — regex stale?")

    registered = set(opencode["provider"]["openrouter"]["models"])
    for model in sorted(skill_models):
        check(
            model in registered,
            f"SKILL.md invokes openrouter/{model} but opencode.jsonc registers "
            f"{sorted(registered)} — opencode rejects unregistered models",
        )
        check(
            model in readme_text,
            f"SKILL.md invokes openrouter/{model} but fusion/README.md does not "
            f"mention it — install docs would register the wrong model",
        )

    # --- no stale registrations pointing at models the skill dropped ---
    for model in sorted(registered - skill_models):
        check(
            False,
            f"opencode.jsonc registers {model} which SKILL.md no longer invokes",
        )

    return report(skill_models)


def report(models=()):
    if failures:
        print(f"FAIL — {len(failures)} consistency problem(s):", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print(f"OK — manifests agree; {len(models)} model ID(s) consistent across "
          f"SKILL.md, opencode.jsonc, and README.md")
    for m in sorted(models):
        print(f"  openrouter/{m}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
