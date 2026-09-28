---
name: hermes-rate-tier-footer
description: "Use when the user wants peak/off-peak cost awareness in the Hermes gateway footer — installs the config-driven rate_tier footer field (DeepSeek built-in, weekend-aware)."
version: 1.1.0
author: chintheman
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, footer, pricing, deepseek, cost, time-of-use]
    homepage: https://github.com/chintheman/rate-tier-footer
    related_skills: [hermes-agent]
---

# Hermes Rate-Tier Footer

Adds a `rate_tier` field to the Hermes gateway runtime footer that shows the
current billing tier (`peak` / `off-peak`) for providers with time-of-use
pricing. DeepSeek is the only major provider with documented peak/off-peak
rates (peak = 2×, 01:00–04:00 + 06:00–10:00 UTC, off-peak all day on Beijing
weekends), so a DeepSeek default is built in — but the windows are
config-driven, so any provider can be added.

**Why it exists:** `hermes insights` was quoting a stale July pricing snapshot
while DeepSeek's real rates were 2–5× higher — a $9.87/week estimate against
~$20 actually burned. Seeing `peak` in the footer at 10:15 SGT made it obvious
when jobs were running at double price, which led to moving six crons off-peak.
Upstream PR: https://github.com/NousResearch/hermes-agent/pull/91448

## How it looks

```
deepseek-v4-flash · 34% · peak · ~          ← during 09:00–12:00 / 14:00–18:00 SGT
deepseek-v4-flash · 12% · off-peak · ~      ← overnight / lunch
claude-sonnet-4-6 · 40% · ~                 ← non-DeepSeek: field silently skipped
```

## Install (two steps)

Step 1, install the skill:

```bash
hermes skills install https://raw.githubusercontent.com/chintheman/rate-tier-footer/main/SKILL.md
```

Step 2, tell your agent: **"Install the rate-tier footer."** Installing the
skill only makes the recipe below available; it does not run it. The recipe
is agent-executable, so the second step is a plain instruction, not another
command to type.

Tested against `NousResearch/hermes-agent` main @
`e408d363393ccb72267e67bcccf4f8954b438cd9`, 2026-09-28. Run
`scripts/check-patch.sh` in this repo after any upstream update to
`gateway/runtime_footer.py` to confirm the patch still applies.

## What this recipe does

An agent executing this skill should complete these steps IN ORDER.

### Step 0 — Locate the Hermes source

```bash
ls ~/.hermes/hermes-agent/gateway/runtime_footer.py
```

- **Found** → git-installed Hermes; the standard path. Continue.
- **Not found** → Hermes may be pip-installed. Locate the package:
  `python3 -c "import gateway.runtime_footer, os; print(os.path.dirname(gateway.runtime_footer.__file__))"`
  (run from the Hermes venv if one exists). Editing site-packages works but is
  overwritten on update — note that to the user; a git install is recommended.

### Step 1 — Check whether it's already installed (idempotent)

```bash
grep -c "rate_tier" ~/.hermes/hermes-agent/gateway/runtime_footer.py
grep -c "rate_windows" ~/.hermes/hermes-agent/gateway/runtime_footer.py
grep -A6 "runtime_footer" "$(hermes config path)"
```

- `rate_tier` AND `rate_windows` present in `runtime_footer.py` → the code is
  already there (this install already has it, or upstream PR #91448 merged).
  **Skip Step 2**, go straight to Step 3 (config) and Step 4 (verify).
- Both absent → apply Step 2.

### Step 2 — Apply the patch

**Preferred (git install, deterministic):**

```bash
cd ~/.hermes/hermes-agent
git apply --check <skill-dir>/references/runtime-footer-rate-tier.patch && \
git apply <skill-dir>/references/runtime-footer-rate-tier.patch
```

`<skill-dir>` is where this skill was installed (find it with
`hermes skills list` or check `~/.hermes/skills/`). If `git apply --check`
fails (tree drifted from upstream main), fall back to the manual insertion
below — do NOT force-apply with `--3way` or `--reject`.

**Fallback (manual insertion):** edit `gateway/runtime_footer.py` with the
agent's patch tool, using these anchors (the current upstream file, with its
merged one-paragraph docstring and ``served_model`` field, is the base):

1. **Module docstring**: add a `rate_tier` field description alongside the
   existing `model`/`context_pct`/`latency`/`served_model`/`cwd` list (opt-in,
   `peak` / `off-peak`, config-driven via `rate_windows`, skipped silently
   when the model matches no window), and append the `rate_windows` block
   documentation (matcher rules, half-open peak hours, `off_peak_days`,
   built-in DeepSeek default) as new paragraphs before the final sentence
   about `gateway/run.py`.
2. **Imports** — after `from __future__ import annotations`, add
   `import datetime as _dt`; after `import os`, add the zoneinfo try/except
   (see the patch file for exact text).
3. **Module constants** — after `_SEP = " · "`, add the `_DEFAULT_RATE_WINDOWS`
   dict (DeepSeek default: `{"deepseek": {"tz": "UTC", "peak": [(1, 4), (6, 10)],
   "off_peak_days": {"tz": "Asia/Shanghai", "days": ["sat", "sun"]}}}`).
4. **Helper functions**: insert `_match_rate_windows`, `_hour_in_tz`,
   `_weekday_in_tz`, `rate_tier_for_model`, `_merge_rate_windows` between
   `_env_cwd()` and `resolve_footer_config` (exact code in the patch file).
5. **`resolve_footer_config`** — add `"rate_windows": _merge_rate_windows(None)`
   to the initial `resolved` dict, and inside the `sections` loop add
   `if isinstance(section.get("rate_windows"), dict): resolved["rate_windows"]
   = _merge_rate_windows(section["rate_windows"])`.
6. **`format_runtime_footer`** — add `rate_windows: Optional[dict[str, Any]] = None`
   as the last keyword parameter; add a `"rate_tier": lambda: rate_tier_for_model(model,
   rate_windows) or ""` entry to the `renderers` dict.
7. **`build_footer_line`**: pass `rate_windows=cfg.get("rate_windows")` in its
   call to `format_runtime_footer`.

The patch file `references/runtime-footer-rate-tier.patch` is the exact
upstream diff — use it as the source of truth for every code block above.

### Step 3 — Enable the config

Add the block below to the Hermes config file (the path printed by
`hermes config path` — open it with `hermes config edit`, merge into the
existing `display:` section):

```yaml
display:
  runtime_footer:
    enabled: true
    fields: [model, context_pct, rate_tier, cwd]
    rate_windows:          # optional — deepseek default is built in
      deepseek:            # model matcher (substring, case-insensitive)
        tz: Asia/Singapore # optional, default UTC
        peak: [[9, 12], [14, 18]]   # half-open [start, end) hours in that tz
        # off_peak_days:             # optional: all-day off-peak rule
        #   tz: Asia/Shanghai        #   weekday checked in THIS tz
        #   days: [sat, sun]         #   never the UTC date
```

Notes:
- `rate_windows` is optional. Omit it to use the built-in DeepSeek UTC default
  (01:00–04:00 + 06:00–10:00 UTC, off-peak all day on Beijing weekends).
- Matchers are **longest-key-first**: a specific key like `deepseek-v4-flash`
  always beats a generic `deepseek`, regardless of config order.
- Peak windows may **wrap midnight** — `[[22, 2]]` means 22:00–01:59 is peak.
- `off_peak_days` marks whole days as off-peak (the DeepSeek weekend rule is
  built in; add it for another provider whose days off-peak differ from its
  hour windows). The weekday is evaluated in the rule's own timezone.
- To add another provider with time-of-use pricing, add a new key under
  `rate_windows` (e.g. `myprovider: {tz: ..., peak: [[...]]}`). The field then
  renders for any model whose id contains that key.
- `fields` must include `rate_tier` — it is opt-in and NOT in the default set.
- Per-platform overrides live under `display.platforms.<platform>.runtime_footer`.
- The user can toggle the whole footer with `/footer on|off` (CLI + gateway).

### Step 4 — Verify (see it before you send it)

```bash
cd ~/.hermes/hermes-agent && python3 - <<'EOF'
from datetime import datetime, timezone
from gateway.runtime_footer import (
    rate_tier_for_model, format_runtime_footer, resolve_footer_config)

peak = datetime(2026, 1, 1, 2, tzinfo=timezone.utc)      # 10:00 SGT = peak
off  = datetime(2026, 1, 1, 13, tzinfo=timezone.utc)     # 21:00 SGT = off-peak
assert rate_tier_for_model("deepseek-v4-flash", now=peak) == "peak"
assert rate_tier_for_model("deepseek-v4-flash", now=off) == "off-peak"
assert rate_tier_for_model("deepseek/deepseek-v4-pro", now=peak) == "peak"
assert rate_tier_for_model("claude-sonnet-4-6", now=peak) is None  # silent skip
# review regressions: Beijing weekend off-peak, midnight-wrapping windows,
# and longest-key matcher precedence
sat = datetime(2026, 8, 22, 2, tzinfo=timezone.utc)      # Beijing Sat 10:00
mon = datetime(2026, 8, 24, 2, tzinfo=timezone.utc)      # Beijing Mon 10:00
assert rate_tier_for_model("deepseek-v4-flash", now=sat) == "off-peak"  # weekend
assert rate_tier_for_model("deepseek-v4-flash", now=mon) == "peak"      # weekday
nightowl = {"nightowl": {"tz": "UTC", "peak": [[22, 2]]}}
assert rate_tier_for_model("nightowl-1", nightowl, now=datetime(2026,1,1,23,tzinfo=timezone.utc)) == "peak"  # wrapped window
win = {"deepseek": {"tz": "UTC", "peak": [[1, 4], [6, 10]]},
       "deepseek-v4-flash": {"tz": "UTC", "peak": [[20, 23]]}}
assert rate_tier_for_model("deepseek-v4-flash", win, now=datetime(2026,1,1,21,tzinfo=timezone.utc)) == "peak"  # specific matcher beats generic
# render checks (time-agnostic — the render uses the live clock)
line = format_runtime_footer(model="deepseek-v4-flash", context_tokens=2048,
                             context_length=8192, fields=["model", "rate_tier"])
assert "peak" in line or "off-peak" in line, line
line2 = format_runtime_footer(model="claude-sonnet-4-6", context_tokens=2048,
                              context_length=8192, fields=["model", "rate_tier"])
assert "peak" not in line2 and "off-peak" not in line2, line2
# custom window authority (Asia/Singapore 09:00-12:00, 14:00-18:00)
cfg = {"rate_windows": {"deepseek": {"tz": "Asia/Singapore", "peak": [[9, 12], [14, 18]]}}}
assert rate_tier_for_model("deepseek-v4-flash", cfg["rate_windows"], now=datetime(2026,1,1,2,tzinfo=timezone.utc)) == "peak"
print("rate_tier: ALL CHECKS PASSED")
EOF
```

Then confirm the installed footer test suite still passes (if pytest is
available): `python3 -m pytest tests/gateway/test_runtime_footer.py -q`.
Finally, restart the gateway (`hermes gateway restart` or `/restart` in
gateway chat) so the new field is picked up, and confirm a live reply shows
the `peak`/`off-peak` token.

## Pitfalls

- **Do NOT double-apply.** The Step 1 check exists because upstream main will
  eventually merge PR #91448. Re-applying the patch after that fails loudly on
  context lines — that's expected, and the correct response is to skip to config.
- **Pip-installed Hermes:** patching site-packages is overwritten on the next
  `hermes update`. Either switch to the git install or accept the field will
  need re-applying after updates.
- **`rate_tier` is opt-in.** Users on the default field set see nothing
  different — the feature never changes an existing footer silently.
- **Only DeepSeek has time-of-use pricing today.** Verified 2026-08-22: Zhipu
  GLM and Moonshot/Kimi both bill flat rates; OpenAI, Anthropic, Google,
  Mistral, xAI, Groq are all flat. The config design is future-proof, but
  there are no other providers to configure yet.
- **Chinese public holidays are not handled.** DeepSeek's current docs say
  peak pricing is also waived on Chinese public holidays, not just weekends.
  This skill only implements the weekday/weekend check (`off_peak_days`), so
  a holiday can render `peak` when DeepSeek is actually billing off-peak.
  There is no holiday calendar built in; treat the field as directionally
  correct and check DeepSeek's live pricing page around holidays if the
  exact tier matters.
- **Keep the snapshot fresh (optional).** Rates drift — the author runs a
  weekly watchdog that scrapes api-docs.deepseek.com and auto-patches
  `agent/usage_pricing.py` + the footer windows when they change
  (see the deepseek-price-sync pattern in the author's Hermes install).
