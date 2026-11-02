#!/usr/bin/env python3
"""Assert the published Fusion plugin is internally consistent.

The failure this exists to prevent actually happened: the repo shipped an
opencode config registering `moonshotai/kimi-k2.7-code` while the skill invoked
`moonshotai/kimi-k3`, so two of six seats died with ProviderModelNotFoundError
for anyone who installed it.

Model IDs live in FOUR places, and the copy-paste block in the README is the one
users actually merge into their own config:

  1. fusion/skills/fusion/SKILL.md        — what the skill invokes  (source of truth)
  2. fusion/opencode/opencode.jsonc       — the file we ship
  3. fusion/README.md seat table          — prose
  4. fusion/README.md ```jsonc block      — what users paste into their config

An earlier version of this script tested `model in readme_text`, which matched
the seat table while the paste block was wrong — a false pass on the exact
regression named above. Sets are now compared for equality in both directions,
and the paste block is parsed as JSON rather than substring-matched.

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

REQUIRED_AGENTS = ("fusion-opus-panelist",)

# Seats retired to fusion/archive/. They must exist there (so they can be
# restored) and must NOT be under agents/, where the plugin would load them.
ARCHIVED_AGENTS = ("fusion-fable-panelist",)

# `openrouter/vendor/model`. The generic placeholder `openrouter/<id>` has no
# inner slash and no word characters in `<id>`, so it is correctly ignored.
MODEL_RE = re.compile(r"openrouter/([\w.-]+/[\w.-]+)")

# Primary seats run on the OpenCode Go subscription. These need no registration,
# but every one must be named in the README so users know what they are paying for.
GO_MODEL_RE = re.compile(r"opencode-go/([\w.-]+)")

# The first ```jsonc fence in the README is the block users merge.
JSONC_FENCE_RE = re.compile(r"```jsonc\n(.*?)```", re.DOTALL)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def strip_jsonc(text):
    """Drop whole-line //-comments so a .jsonc file parses as JSON.

    Anchored to line start, so a `//` inside a string value (a URL, say) is
    left alone.
    """
    return re.sub(r"^\s*//.*$", "", text, flags=re.MULTILINE)


def registered_models(blob, label):
    """Model IDs registered under provider.openrouter.models, or None."""
    try:
        data = json.loads(strip_jsonc(blob))
    except json.JSONDecodeError as exc:
        check(False, f"{label} is not parseable JSON/JSONC: {exc}")
        return None
    try:
        return set(data["provider"]["openrouter"]["models"])
    except (KeyError, TypeError):
        check(False, f"{label} has no provider.openrouter.models map")
        return None


def compare(skill_models, found, label):
    """Assert a registration site matches the skill exactly, both directions."""
    if found is None:
        return
    for missing in sorted(skill_models - found):
        check(False, f"{label}: SKILL.md invokes openrouter/{missing} but it is "
                     f"not registered there — opencode rejects unregistered models")
    for stale in sorted(found - skill_models):
        check(False, f"{label}: registers {stale}, which SKILL.md does not "
                     f"invoke — stale entry will send users to a dead model")


def main():
    for path in (MARKETPLACE, PLUGIN, SKILL, OPENCODE, PLUGIN_README):
        check(path.exists(), f"missing required file: {path.relative_to(ROOT)}")
    if failures:
        return report()

    marketplace = json.loads(MARKETPLACE.read_text())
    plugin = json.loads(PLUGIN.read_text())
    skill_text = SKILL.read_text()
    readme_text = PLUGIN_README.read_text()

    # --- manifests agree with each other and point at a real plugin ---
    entries = {p["name"]: p for p in marketplace.get("plugins", [])}
    check(
        plugin["name"] in entries,
        f"plugin.json name {plugin['name']!r} is not listed in marketplace.json "
        f"(listed: {sorted(entries)})",
    )
    if plugin["name"] in entries:
        source = ROOT / entries[plugin["name"]]["source"]
        check(source.is_dir(), f"marketplace.json source is not a directory: {source}")
        # A source that merely exists is not enough — it must BE a plugin.
        manifest = source / ".claude-plugin" / "plugin.json"
        check(
            manifest.exists(),
            f"marketplace.json source {source.name!r} has no "
            f".claude-plugin/plugin.json — install would resolve but load nothing",
        )
        if manifest.exists():
            check(
                json.loads(manifest.read_text())["name"] == plugin["name"],
                f"plugin name at {manifest} disagrees with marketplace entry",
            )

    # --- conventional component dirs are where Claude Code looks ---
    plugin_dir = ROOT / "fusion"
    check(
        (plugin_dir / "skills" / "fusion" / "SKILL.md").exists(),
        "skill must live at fusion/skills/fusion/SKILL.md for auto-discovery",
    )
    for agent in REQUIRED_AGENTS:
        check(
            (plugin_dir / "agents" / f"{agent}.md").exists(),
            f"missing agent fusion/agents/{agent}.md — the skill's Panel Roster "
            f"names it, so shipping without it yields a seat that cannot start",
        )

    for agent in ARCHIVED_AGENTS:
        check(
            (plugin_dir / "archive" / f"{agent}.md").exists(),
            f"archived agent fusion/archive/{agent}.md is missing — it cannot be restored",
        )
        check(
            not (plugin_dir / "agents" / f"{agent}.md").exists(),
            f"archived agent {agent} is also under fusion/agents/ — the plugin would load it",
        )

    # --- every model the skill invokes is registered in every place ---
    skill_models = set(MODEL_RE.findall(skill_text))
    check(skill_models, "no openrouter model IDs found in SKILL.md — regex stale?")

    compare(skill_models, registered_models(OPENCODE.read_text(), "opencode.jsonc"),
            "opencode.jsonc")

    fence = JSONC_FENCE_RE.search(readme_text)
    check(fence, "fusion/README.md has no ```jsonc block — users have nothing to "
                 "copy into their opencode config")
    if fence:
        compare(skill_models,
                registered_models(fence.group(1), "the README ```jsonc block"),
                "README paste block")

    # --- prose mentions every model too (weaker, but catches a stale table) ---
    for model in sorted(skill_models):
        check(model in readme_text,
              f"fusion/README.md never mentions {model}")

    go_models = set(GO_MODEL_RE.findall(skill_text))
    check(go_models, "no opencode-go model IDs found in SKILL.md — regex stale?")
    check(len(go_models) == len(skill_models),
          f"SKILL.md has {len(go_models)} OpenCode Go primaries but "
          f"{len(skill_models)} OpenRouter fallbacks — every opencode seat needs both")
    for model in sorted(go_models):
        check(model in readme_text,
              f"fusion/README.md never mentions OpenCode Go model {model}")

    return report(skill_models)


def report(models=()):
    if failures:
        print(f"FAIL — {len(failures)} consistency problem(s):", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print(f"OK — manifests agree; {len(models)} model ID(s) consistent across "
          f"SKILL.md, opencode.jsonc, and both README sites")
    for m in sorted(models):
        print(f"  openrouter/{m}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
