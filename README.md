# Hermes Rate-Tier Footer

Show **peak / off-peak billing** in your Hermes gateway footer, so you can see
at a glance when every reply is costing double.

```
deepseek-v4-flash · 34% · peak · ~          ← during 09:00–12:00 / 14:00–18:00 SGT
deepseek-v4-flash · 12% · off-peak · ~      ← overnight / lunch
claude-sonnet-4-6 · 40% · ~                 ← non-DeepSeek: field silently skipped
```

## Why

Hermes' usage estimator was quoting a stale July pricing snapshot while
DeepSeek's live rates were **2–5× higher** — a `$9.87`/week estimate against
~`$20` actually burned. DeepSeek bills **peak = 2× off-peak**
(peak: 01:00–04:00 + 06:00–10:00 UTC; off-peak is half price), so *when* you
run matters as much as *how much* you run. The `rate_tier` footer field makes
the billing tier visible on every reply, and made it obvious enough to move
six scheduled jobs out of peak hours — halving their token cost.

DeepSeek is the **only** major LLM provider with documented time-of-use
pricing (verified 2026-08-21: Zhipu GLM and Moonshot/Kimi are flat; so are
OpenAI, Anthropic, Google, Mistral, xAI, Groq). The implementation is
config-driven, so if another provider ever adopts peak/off-peak pricing, you
just add their windows — no code change.

## Install (one command)

```bash
hermes skills install https://raw.githubusercontent.com/chintheman/rate-tier-footer/main/SKILL.md
```

Then tell your agent: **"Install the rate-tier footer."** The skill contains
an executable recipe: it checks whether the code is already present (it is,
once [PR #90921](https://github.com/NousResearch/hermes-agent/pull/90921)
merges upstream), applies the patch if not, enables the config, and verifies
with a render check.

Requires the git-installed Hermes source at `~/.hermes/hermes-agent/` (the
default from the official installer). Pip installs work but the patch is
overwritten on update.

### Manual install

1. Copy `references/runtime-footer-rate-tier.patch` into the repo root and:
   ```bash
   cd ~/.hermes/hermes-agent
   git apply --check runtime-footer-rate-tier.patch && git apply runtime-footer-rate-tier.patch
   ```
   (If the tree drifted from upstream main, insert the code manually per the
   step-by-step recipe in `SKILL.md`.)
2. Enable the field in `~/.hermes/config.yaml`:
   ```yaml
   display:
     runtime_footer:
       enabled: true
       fields: [model, context_pct, rate_tier, cwd]
       # optional — DeepSeek's windows are built in; add any future provider here
       rate_windows:
         deepseek:
           tz: Asia/Singapore
           peak: [[9, 12], [14, 18]]
   ```
3. Restart the gateway (`/restart` in gateway chat, or `hermes gateway restart`).

## How it works

- The footer reads the **active model** at render time — no config per model.
- `rate_tier` matches that model id (case-insensitive substring) against
  `display.runtime_footer.rate_windows`.
- DeepSeek's windows ship as a built-in default; user config **deep-merges**
  over it, so a partial map keeps DeepSeek working.
- Non-matching models (Claude, GPT, Gemini…) render no tier — silently, no
  noise, no footer change for anyone not on a tiered provider.
- `rate_tier` is opt-in: it is NOT in the default field set.

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Agent-executable recipe (check → patch → config → verify) |
| `references/runtime-footer-rate-tier.patch` | Exact upstream diff for `gateway/runtime_footer.py` |
| `README.md` | This file |

## Credits

- Feature + pricing fix: [chintheman](https://github.com/chintheman) ·
  upstream PR: [NousResearch/hermes-agent#90921](https://github.com/NousResearch/hermes-agent/pull/90921)
- Rates verified live against https://api-docs.deepseek.com/quick_start/pricing (2026-08-20)
- MIT — build on it, share it, send it to your agent.
