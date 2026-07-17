# Progress Tracker

## Current Phase
**Phase 3 — MT5 → Bridge Connected**

## Current Step
**3.3 — June 1–5 2026 replay — run `tools/backtest_replay.py tools/june_2026_replay.txt` against live Bridge; review LLM decisions against benchmark**

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

### Phase 2 — MT5 Formula Layer (complete)
- [x] 2.1 — `mt5/Include/LEINTUMEngine/Defines.mqh` — all structs,
      enums, constants; no duplicate definitions; compiles clean
- [x] 2.2 — `mt5/Include/LEINTUMEngine/PriceFabric.mqh` — `Refresh()`
      fetches OHLCV for 8 TFs + 6 instruments; correct bar counts
      confirmed in Expert log
- [x] 2.3 — `mt5/Include/LEINTUMEngine/SessionProfile.mqh` — SVR
      computed; state correctly resolves to SPIKE/HOT/NORMAL/QUIET;
      `slMultiplier` clamped
- [x] 2.4 — `mt5/Include/LEINTUMEngine/RegimeDetector.mqh` — DER, Hurst,
      RBE computed; `regime_strength` clamped to [0,1] confirmed across
      test run; deceleration flag works
- [x] 2.5 — `mt5/Include/LEINTUMEngine/MomentumPhase.mqh` — NPV, IER,
      acceleration, jerk computed; phase correctly resolves to
      WAXING/WANING/NEUTRAL/EXHAUSTED
- [x] 2.6 — `mt5/Include/LEINTUMEngine/ConditionAssessor.mqh` — VWAP
      value area, SDS, BQS computed; `in_value` bool correct
- [x] 2.7 — `mt5/Include/LEINTUMEngine/ContextAnalyzer.mqh` — HTF flow
      scores for H1/H4/D1; consensus + agree_count correct; H4 confirmed
      at 2x weight
- [x] 2.8 — `mt5/Include/LEINTUMEngine/CorrelationMonitor.mqh` —
      per-pair energy state, net dir, velocity reversal; DEAD pairs
      excluded from consensus
- [x] 2.9 — `mt5/Include/LEINTUMEngine/TradeHealthMonitor.mqh` —
      5-component HealthScore [0,100]; `emergencyExit` bool fires below 25
- [x] 2.10 — `mt5/Include/LEINTUMEngine/MarketStatePackager.mqh` —
      `Serialize()` outputs valid JSON; verified zero errors on
      jsonlint.com; all fields labeled
- [x] 2.11 — `mt5/Include/LEINTUMEngine/RiskManager.mqh` — conviction
      gate, spread gate, daily loss limit, lot sizing all enforced
- [x] 2.12 — `mt5/Experts/LEINTUM_Engine.mq5` (formula loop only) —
      compiles clean; Strategy Tester run confirms regime/momentum
      output every bar; no execution logic present yet
- [x] 2.13 — Phase 2 gate — all 6 gate checks in `ai-workflow-rules.md`
      pass

---

## In Progress

### Phase 3 — MT5 → Bridge Connected
- [x] 3.1 — `mt5/Include/LEINTUMEngine/BridgeClient.mqh` — EA POSTs
      payload to Bridge; Bridge console shows received JSON
- [x] 3.2 — Bridge logging of MT5 payloads — every received payload
      logged to session JSONL; LLM response printed to MT5 Expert log;
      NO execution
- [x] 3.3 — June 1–5 2026 replay — `tools/backtest_replay.py` built
      and verified; first replay run completed (384 bars, 0 errors);
      `MarketStatePackager.mqh` patched to include OHLC prices in
      `current_bar` payload; second replay confirmed prices now flow
      correctly to the LLM (16 non-fallback trade decisions).
- [x] 3.4 — System prompt iteration — two-iteration upgrade:
      (1) Institutional Analyst model — removed rigid kill-switches,
      added Analytical Synthesis + "Price is Truth" override;
      (2) Prior-bar memory — `backtest_replay.py` now injects a 5-bar
      rolling history (`prior_bars`) into each payload; system prompt
      updated to teach the LLM to use `prior_bars` for spotting
      Distribution Tops and Accumulation Floors across multiple bars.
      All changes logged in `docs/SYSTEM_PROMPT_NOTES.md`.
- [/] 3.5 — Phase 3 gate — pending benchmark re-run with prior_bars;
      gate checks in `ai-workflow-rules.md` not yet fully verified.

---

## Open Questions

- What is the Anthropic API key environment? (Personal account or
  new account dedicated to LEINTUM?)
- VPS decision deferred to Phase 6 — Bridge runs locally for Phases
  1–5.
- Telegram bot token: not yet created. Needed for Phase 4.
- Economic calendar source for production `macro_calendar` field —
  deferred post-Phase 5; hardcoded for June 1–5 2026 test week
  (built in Phase 2 step 2.10).

---

## Deferred / Known Issues

- `system_prompt.txt` is still a first draft until the Phase 3
  benchmark replay test passes. Expect 2–4 iterations during this
  phase — this is the current phase's primary quality gate.
- Live economic calendar API integration deferred post-Phase 5;
  currently hardcoded for the June 1–5 2026 test week only.

---

## Architecture Decisions

- Bridge model name read from `process.env.LLM_MODEL` — never
  hardcoded in source. Operator sets this in `.env` at deploy time.
- `bridge/fallback.js` was built before `llm.js` to avoid a broken
  import on first run — both written in the same Phase 1 prompt.
- Every composite score (`regime_strength`, `confidence`,
  `health_score`, etc.) is clamped to its defined range at the point
  of computation in the MQL5 module, not downstream — confirmed
  across all Phase 2 modules. This directly fixes the unclamped
  regime-strength bug found in the original one-month backtest.
- `CPriceFabric` is the single OHLCV source for every formula module
  — no module calls `Copy*` directly. Confirmed during Phase 2 build.
- `tools/backtest_replay.py` uses Python standard library only
  (urllib.request, json, sys, time, argparse) — no pip install
  required. MT5's WebRequest is sandboxed inside Strategy Tester
  agents, so this script is the workaround for the Phase 3.3
  benchmark replay. Input format: one JSON payload per line (.txt);
  blank lines and MT5 log prefixes handled automatically; one
  failed bar never stops the run.
- `SBarAnatomy` in `Defines.mqh` always declared `open`, `high`,
  `low`, `close` fields. `MarketStatePackager.mqh` was not serialising
  them, causing the LLM to hallucinate prices when the schema required
  `entry.price`. Fixed by adding OHLC fields at the top of the
  `current_bar` JSON block (additive change, schema v1.0 unchanged).
  `bridge/system_prompt.txt` updated to tell Claude these fields exist.
  `context/code-standards.md` updated to document the additive change.

---

## Session Notes

- Phase 3 is a wiring-and-observation phase, not a feature-build
  phase: `BridgeClient.mqh` sends payloads and decisions are logged,
  **not executed**. Do not let `DecisionExecutor` logic creep in here
  — that's Phase 4.
- The June 1–5 2026 replay (step 3.3) and the Phase 3 benchmark
  acceptance test (the Tuesday 16:00 June 2 2026 bar — four failed
  tests of 1.08522 followed by a distribution break on volume drop)
  are the same gate referenced in `ai-workflow-rules.md`. Do not mark
  3.4 done until that specific bar passes.
- Every system prompt change made during Phase 3 must be recorded in
  `docs/SYSTEM_PROMPT_NOTES.md` — this file doesn't exist yet and
  should be created as part of step 3.4.