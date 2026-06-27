# Progress Tracker

## Current Phase
**Phase 1 — Bridge in isolation (no MT5)**

## Current Step
**1.3 — `bridge/llm.js` — Anthropic SDK caller + 8s timeout + fallback**

---

## Completed

### Environment Setup
- [x] Repo created at `E:\LEINTUM\AGENT-TRADE`
- [x] Folder structure created: `context/`, `context/specs/`,
      `tools/sample_payloads/`, `logs/`, `bridge/`, `mt5/`,
      `dashboard/`
- [x] Context files committed: `CLAUDE.md`, `context/project-overview.md`,
      `context/architecture.md`, `context/formulas.md`
- [x] Missing context files generated: `context/ui-context.md`,
      `context/code-standards.md`, `context/ai-workflow-rules.md`,
      `context/progress-tracker.md`, `context/specs/00-build-plan.md`

### Phase 1 — Bridge
- [x] 1.1 — `npm init` + install packages in `bridge/`
      (`express`, `@anthropic-ai/sdk`, `zod`, `dotenv`, `pm2` installed;
      `package.json` and `package-lock.json` committed)
- [x] 1.2 — `bridge/server.js` with `/heartbeat`, `/alert`, `/status`
      (stub HOLD responses; `bridge/.gitignore` and
      `bridge/.env.example` created)
      Verified: `node server.js` boots, `/status` returns `{ok:true}`,
      `/heartbeat` logs body and returns hardcoded HOLD stub.

---

## In Progress

### Phase 1 — Bridge (continued)
- [ ] 1.3 — `bridge/llm.js` — Anthropic SDK caller + 8s timeout + fallback
- [ ] 1.4 — `bridge/validator.js` — Zod schema for decision response
- [ ] 1.5 — `bridge/logger.js` — JSONL append writer
- [ ] 1.6 — `bridge/fallback.js` — static HOLD response constructor
- [ ] 1.7 — `bridge/system_prompt.txt` — first draft (5 sections)
- [ ] 1.8 — `bridge/ecosystem.config.js` — PM2 config
- [ ] 1.9 — `tools/prompt_tester.js` — send sample payloads, print response
- [ ] 1.10 — `tools/sample_payloads/` — 5 reference JSONs
- [ ] 1.11 — Phase 1 gate: all 6 checklist items pass

---

## Open Questions

- What is the Anthropic API key environment? (Personal account or
  new account dedicated to LEINTUM?)
- VPS decision deferred to Phase 6 — Bridge runs locally for Phases
  1–5.
- Telegram bot token: not yet created. Needed for Phase 4.

---

## Deferred / Known Issues

- `system_prompt.txt` is a first draft until the Phase 3 benchmark
  replay test passes. Expect 2–4 iterations.
- Economic calendar for the macro_calendar payload field: hardcoded
  for the June 1–5 2026 test week in Phase 2. A live calendar API
  integration is deferred post-Phase 5.

---

## Session Notes

- `bridge/llm.js` must read model name from `process.env.LLM_MODEL`
  — never hardcode a model string. Confirm current recommended Claude
  Sonnet model identifier against Anthropic docs before wiring in.
- The hardcoded HOLD stub in `server.js` (`/heartbeat` and `/alert`)
  will be replaced in step 1.3 once `llm.js` is wired in and proven.
- `bridge/fallback.js` (step 1.6) must be written before `llm.js`
  imports it — or write them together in the same prompt so the
  import doesn't break on first run.