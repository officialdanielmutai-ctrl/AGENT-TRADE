# Progress Tracker

## Current Phase
**Phase 2 — MT5 Formula Layer**

## Current Step
**2.1 — `mt5/Include/LEINTUMEngine/Defines.mqh` — all structs, enums, constants**

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

### Phase 1 — Bridge (complete)
- [x] 1.1 — `bridge/package.json` — `npm install` completed; `node_modules`
      populated (`express`, `@anthropic-ai/sdk`, `zod`, `dotenv`, `pm2`)
- [x] 1.2 — `bridge/server.js` — server starts on port 3001; `/status`
      returns `{"ok":true}`; stub HOLD on `/heartbeat` and `/alert`
- [x] 1.3 — `bridge/llm.js` — Anthropic SDK caller; `AbortController`
      8s timeout fires correctly; falls back to HOLD on timeout or error;
      model name read from `process.env.LLM_MODEL`
- [x] 1.4 — `bridge/validator.js` — Zod schema for full decision response;
      valid response passes; malformed response throws `ZodError`
- [x] 1.5 — `bridge/logger.js` — JSONL append writer; each call logged as
      one-line JSON to `logs/session_YYYY-MM-DD.jsonl`
- [x] 1.6 — `bridge/fallback.js` — static HOLD response constructor;
      returns valid HOLD struct with `"fallback": true`
- [x] 1.7 — `bridge/system_prompt.txt` — first draft; all 5 sections
      present (identity, measurement framework, decision protocol,
      management protocol, response schema). Will iterate in Phase 3.
- [x] 1.8 — `bridge/.env.example` + `bridge/ecosystem.config.js` —
      all required keys documented; PM2 starts Bridge cleanly
- [x] 1.9 — `tools/prompt_tester.js` — reads payload file, POSTs to
      `/heartbeat`, prints full response
- [x] 1.10 — `tools/sample_payloads/` — 5 reference JSONs created:
      `clear_sell.json`, `clear_buy.json`, `mixed_hold.json`,
      `spike_session.json`, `post_nfp_trend.json`
- [x] 1.11 — Phase 1 gate — all 6 checklist items in
      `ai-workflow-rules.md` pass

---

## In Progress

### Phase 2 — MT5 Formula Layer
- [ ] 2.1 — `mt5/Include/LEINTUMEngine/Defines.mqh` — all structs,
      enums, constants; no duplicate definitions; compiles clean
- [ ] 2.2 — `mt5/Include/LEINTUMEngine/PriceFabric.mqh` — `Refresh()`
      fetches OHLCV for 8 TFs + 6 instruments; correct bar counts
- [ ] 2.3 — `mt5/Include/LEINTUMEngine/SessionProfile.mqh` — SVR; state
      is one of SPIKE/HOT/NORMAL/QUIET; `slMultiplier` clamped
- [ ] 2.4 — `mt5/Include/LEINTUMEngine/RegimeDetector.mqh` — DER, Hurst,
      RBE; `regime_strength` clamped to [0,1]; deceleration flag works
- [ ] 2.5 — `mt5/Include/LEINTUMEngine/MomentumPhase.mqh` — NPV, IER,
      acceleration, jerk; phase is WAXING/WANING/NEUTRAL/EXHAUSTED
- [ ] 2.6 — `mt5/Include/LEINTUMEngine/ConditionAssessor.mqh` — VWAP
      value area, SDS, BQS; `in_value` bool correct
- [ ] 2.7 — `mt5/Include/LEINTUMEngine/ContextAnalyzer.mqh` — HTF flow
      scores for H1/H4/D1; consensus + agree_count; H4 gets 2x weight
- [ ] 2.8 — `mt5/Include/LEINTUMEngine/CorrelationMonitor.mqh` — per-pair
      energy state, net dir, velocity reversal; DEAD pairs excluded
- [ ] 2.9 — `mt5/Include/LEINTUMEngine/TradeHealthMonitor.mqh` — 5-component
      HealthScore [0,100]; `emergencyExit` bool fires below 25
- [ ] 2.10 — `mt5/Include/LEINTUMEngine/MarketStatePackager.mqh` —
      `Serialize()` outputs valid JSON; jsonlint.com zero errors; all
      fields labeled
- [ ] 2.11 — `mt5/Include/LEINTUMEngine/RiskManager.mqh` — conviction
      gate, spread gate, daily loss limit, lot sizing enforced
- [ ] 2.12 — `mt5/Experts/LEINTUM_Engine.mq5` (formula loop only) —
      compiles; Strategy Tester shows regime/momentum output every bar;
      no execution yet
- [ ] 2.13 — Phase 2 gate — all 6 gate checks in `ai-workflow-rules.md`
      pass

---

## Open Questions

- What is the Anthropic API key environment? (Personal account or
  new account dedicated to LEINTUM?)
- VPS decision deferred to Phase 6 — Bridge runs locally for Phases
  1–5.
- Telegram bot token: not yet created. Needed for Phase 4.
- Economic calendar source for production `macro_calendar` field —
  deferred post-Phase 5; hardcoded for June 1–5 2026 test week in
  Phase 2 step 2.10.

---

## Deferred / Known Issues

- `system_prompt.txt` is a first draft until the Phase 3 benchmark
  replay test passes. Expect 2–4 iterations during Phase 3.
- Economic calendar for the `macro_calendar` payload field: hardcoded
  for the June 1–5 2026 test week in Phase 2. Live calendar API
  integration deferred post-Phase 5.

---

## Architecture Decisions

- Bridge model name read from `process.env.LLM_MODEL` — never
  hardcoded in source. Operator sets this in `.env` at deploy time.
- `bridge/fallback.js` was built before `llm.js` to avoid a broken
  import on first run — both written in the same Phase 1 prompt.
- Phase 2 critical rule: every composite score (`regime_strength`,
  `confidence`, `health_score`, etc.) is clamped to its defined range
  at the point of computation in the MQL5 module — not downstream.
  This directly addresses the unclamped regime-strength bug found in
  the one-month backtest. See `architecture.md` Invariant 8.

---

## Session Notes

- Phase 2 starts with `Defines.mqh` — reshape structs first, confirm
  zero compile errors, then build each module against the new shapes.
  Do not change struct layout and module logic in the same step.
- Build order within Phase 2 matters: `Defines.mqh` → `PriceFabric`
  → then modules one at a time. Each module reads from `CPriceFabric`
  only — no direct `Copy*` calls inside individual modules.
- `LEINTUM_Engine.mq5` in step 2.12 runs formula modules only — no
  `BridgeClient`, no `DecisionExecutor` yet. Those come in Phases 3
  and 4.