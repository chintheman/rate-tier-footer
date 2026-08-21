---
name: hermes-rate-tier-footer
description: "Use when the user wants peak/off-peak cost awareness in the Hermes gateway footer — installs the config-driven rate_tier footer field (DeepSeek built-in)."
version: 1.0.0
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
rates (peak = 2×, 01:00–04:00 + 06:00–10:00 UTC), so a DeepSeek default is
built in — but the windows are config-driven, so any provider can be added.

**Why it exists:** `hermes insights` was quoting a stale July pricing snapshot
while DeepSeek's real rates were 2–5× higher — a $9.87/week estimate against
~$20 actually burned. Seeing `peak` in the footer at 10:15 SGT made it obvious
when jobs were running at double price, which led to moving six crons off-peak.
Upstream PR: https://github.com/NousResearch/hermes-agent/pull/90921

## How it looks

```
deepseek-v4-flash · 34% · peak · ~          ← during 09:00–12:00 / 14:00–18:00 SGT
deepseek-v4-flash · 12% · off-peak · ~      ← overnight / lunch
claude-sonnet-4-6 · 40% · ~                 ← non-DeepSeek: field silently skipped
```

## Install

```bash
hermes skills install https://raw.githubusercontent.com/chintheman/rate-tier-footer/main/SKILL.md
```

Then tell your agent: **"Install the rate-tier footer"** (or just load this
skill and run it — the recipe below is agent-executable).

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
  already there (this install already has it, or upstream PR #90921 merged).
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
agent's patch tool, using these anchors (the upstream file is the base):

1. **Module docstring** — after the `cwd` field line, add:
   ```
       rate_tier    — billing tier for the current hour (``peak`` / ``off-peak``)
                      for providers with time-of-use pricing, e.g. DeepSeek's
                      peak/off-peak rates. Config-driven and model-agnostic — see
                      ``rate_windows`` below. Skipped silently when the active
                      model matches no configured window.
   ```
   and change the opt-in note from "``latency`` is opt-in" to
   "``latency`` and ``rate_tier`` are opt-in".
2. **Imports** — after `from __future__ import annotations`, add
   `import datetime as _dt`; after `import os`, add the zoneinfo try/except
   (see the patch file for exact text).
3. **Module constants** — after `_SEP = " · "`, add the `_DEFAULT_RATE_WINDOWS`
   dict (DeepSeek default: `{"deepseek": {"tz": "UTC", "peak": [(1, 4), (6, 10)]}}`).
4. **Helper functions** — insert `_DEEPSEEK_PEAK_WINDOWS_UTC`,
   `_is_deepseek_model`, `deepseek_rate_tier`, `_match_rate_windows`,
   `_hour_in_tz`, `rate_tier_for_model`, `_merge_rate_windows` after
   `_model_short(...)` (exact code in the patch file).
5. **`resolve_footer_config`** — add `"rate_windows": _merge_rate_windows(None)`
   to the initial `resolved` dict, and merge user windows in both the global
   and platform branches (`_merge_rate_windows(global_cfg["rate_windows"])`).
6. **`format_runtime_footer`** — add `rate_windows: Optional[dict[str, Any]] = None`
   parameter; add the `elif field == "rate_tier":` branch (render
   `rate_tier_for_model(model, rate_windows)` only when not None).
7. **`build_footer_line`** — pass `rate_windows=cfg.get("rate_windows")`.

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
```

Notes:
- `rate_windows` is optional. Omit it to use the built-in DeepSeek UTC default.
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
  eventually merge PR #90921. Re-applying the patch after that fails loudly on
  context lines — that's expected, and the correct response is to skip to config.
- **Pip-installed Hermes:** patching site-packages is overwritten on the next
  `hermes update`. Either switch to the git install or accept the field will
  need re-applying after updates.
- **`rate_tier` is opt-in.** Users on the default field set see nothing
  different — the feature never changes an existing footer silently.
- **Only DeepSeek has time-of-use pricing today.** Verified 2026-08-21: Zhipu
  GLM and Moonshot/Kimi both bill flat rates; OpenAI, Anthropic, Google,
  Mistral, xAI, Groq are all flat. The config design is future-proof, but
  there are no other providers to configure yet.
- **Keep the snapshot fresh (optional).** Rates drift — the author runs a
  weekly watchdog that scrapes api-docs.deepseek.com and auto-patches
  `agent/usage_pricing.py` + the footer windows when they change
  (see the deepseek-price-sync pattern in the author's Hermes install).
