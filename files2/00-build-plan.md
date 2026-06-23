# Build Plan — Full Unit List

All build units in phase order. Each unit is one Aider prompt scope.
Check off each unit in `progress-tracker.md` when its "done when"
condition passes.

---

## Phase 1 — Bridge in Isolation

| Unit | File | Done when |
|---|---|---|
| 1.1 | `bridge/package.json` | `npm install` completes, `node_modules` populated |
| 1.2 | `bridge/server.js` | Server starts on port 3001; `/status` returns `{"ok":true}` |
| 1.3 | `bridge/llm.js` | `callLLM(systemPrompt, payload)` returns parsed JSON or fallback HOLD; timeout fires at 8s |
| 1.4 | `bridge/validator.js` | Valid response passes; malformed response throws ZodError |
| 1.5 | `bridge/logger.js` | Each call appended as one-line JSON to `logs/session_YYYY-MM-DD.jsonl` |
| 1.6 | `bridge/fallback.js` | Returns a valid HOLD response struct with `"fallback": true` |
| 1.7 | `bridge/system_prompt.txt` | First draft covering all 5 sections (identity, measurement framework, decision protocol, management protocol, response schema) |
| 1.8 | `bridge/.env.example` + `bridge/ecosystem.config.js` | `.env.example` has all required keys; PM2 starts the Bridge cleanly |
| 1.9 | `tools/prompt_tester.js` | Reads a payload file, calls the Bridge `/heartbeat`, prints the full response |
| 1.10 | `tools/sample_payloads/` (5 files) | clear_sell.json, clear_buy.json, mixed_hold.json, spike_session.json, post_nfp_trend.json |
| 1.11 | Phase 1 gate | All 6 gate checks in `ai-workflow-rules.md` pass |

---

## Phase 2 — MT5 Formula Layer

| Unit | File | Done when |
|---|---|---|
| 2.1 | `mt5/Include/LEINTUMEngine/Defines.mqh` | All structs, enums, constants compile; no duplicate definitions |
| 2.2 | `mt5/Include/LEINTUMEngine/PriceFabric.mqh` | `Refresh()` fetches OHLCV for 8 TFs + 6 instruments; Expert log shows correct bar counts |
| 2.3 | `mt5/Include/LEINTUMEngine/SessionProfile.mqh` | SVR computed correctly; state is one of SPIKE/HOT/NORMAL/QUIET; `slMultiplier` is clamped |
| 2.4 | `mt5/Include/LEINTUMEngine/RegimeDetector.mqh` | DER, Hurst, RBE computed; `regime_strength` clamped to [0,1]; deceleration flag works |
| 2.5 | `mt5/Include/LEINTUMEngine/MomentumPhase.mqh` | NPV, IER, acceleration, jerk computed; phase is one of WAXING/WANING/NEUTRAL/EXHAUSTED |
| 2.6 | `mt5/Include/LEINTUMEngine/ConditionAssessor.mqh` | VWAP value area, SDS, BQS computed; `in_value` bool correct |
| 2.7 | `mt5/Include/LEINTUMEngine/ContextAnalyzer.mqh` | HTF flow scores for H1/H4/D1; consensus + agree_count correct; H4 gets 2x weight |
| 2.8 | `mt5/Include/LEINTUMEngine/CorrelationMonitor.mqh` | Per-pair energy state, net dir, velocity reversal; DEAD pairs excluded from consensus |
| 2.9 | `mt5/Include/LEINTUMEngine/TradeHealthMonitor.mqh` | 5-component HealthScore [0,100]; `emergencyExit` bool fires below 25 |
| 2.10 | `mt5/Include/LEINTUMEngine/MarketStatePackager.mqh` | `Serialize()` outputs valid JSON; jsonlint.com zero errors; all fields labeled |
| 2.11 | `mt5/Include/LEINTUMEngine/RiskManager.mqh` | Conviction gate, spread gate, daily loss limit, lot sizing all enforced |
| 2.12 | `mt5/Experts/LEINTUM_Engine.mq5` (formula loop only) | Compiles; Strategy Tester run shows regime/momentum output every bar; no execution yet |
| 2.13 | Phase 2 gate | All 6 gate checks in `ai-workflow-rules.md` pass |

---

## Phase 3 — MT5 → Bridge Connected

| Unit | File | Done when |
|---|---|---|
| 3.1 | `mt5/Include/LEINTUMEngine/BridgeClient.mqh` | EA POSTs payload to Bridge; Bridge console shows received JSON |
| 3.2 | Bridge logging of MT5 payloads | Every received payload logged to session JSONL; LLM response printed to MT5 Expert log; NO execution |
| 3.3 | June 1–5 2026 replay | LLM decisions reviewed against benchmark (see `ai-workflow-rules.md`); decision quality documented |
| 3.4 | System prompt iteration | Benchmark pass condition met; all changes logged in `docs/SYSTEM_PROMPT_NOTES.md` |
| 3.5 | Phase 3 gate | All 5 gate checks in `ai-workflow-rules.md` pass |

---

## Phase 4 — Execution Layer + Event System

| Unit | File | Done when |
|---|---|---|
| 4.1 | `mt5/Include/LEINTUMEngine/DecisionExecutor.mqh` | OPEN_SELL conviction 0.82 places order; conviction 0.42 rejected + logged; spread gate works |
| 4.2 | `mt5/Include/LEINTUMEngine/EventTriggerMonitor.mqh` | All 8 watch conditions registered; REGIME_CHANGE fires intra-bar in tester |
| 4.3 | Full management cycle wired in `LEINTUM_Engine.mq5` | HealthScore < 25 → emergency close; SL tightens at 25–50; BE lock fires at 1R |
| 4.4 | `dashboard/viewer.html` | Opens in browser; reads JSONL; colour-coded cards; expand shows full reasoning |
| 4.5 | `bridge/telegram.js` + alerts wired | Test notification received on phone within 5s of trigger |
| 4.6 | `dashboard/live.html` + `dashboard/ws_server.js` | Live dashboard shows current state; updates on each heartbeat |
| 4.7 | Phase 4 gate | All 4 gate checks in `ai-workflow-rules.md` pass |

---

## Phase 5 — Demo Forward Test

| Unit | Action | Done when |
|---|---|---|
| 5.1 | Connect to demo account, 0.01 lots, run 2 weeks | 10 consecutive days, no Bridge crash, no unhandled exception |
| 5.2 | Nightly log review + prompt iteration | Top-3 prompt weaknesses identified and addressed |
| 5.3 | Metrics review | Max drawdown < 20 pips/trade; 1–3 trades/day avg; > 85% reasoning quality |
| 5.4 | Fallback stress test | Bridge disconnected mid-session → fallback fires → reconnects → resumes |

---

## Phase 6 — Live Deployment

| Unit | Action |
|---|---|
| 6.1 | Deploy Bridge on VPS or co-located machine |
| 6.2 | Set position sizing at 0.5% risk per trade |
| 6.3 | Enable PM2 + log rotation |
| 6.4 | Confirm all Telegram alerts active |
| 6.5 | Schedule weekly system prompt review |

---

## Spec Files (one per phase)

Create these as each phase begins:

- `context/specs/01-bridge.md` — detailed unit specs for Phase 1
- `context/specs/02-mt5-formulas.md` — detailed unit specs for Phase 2
- `context/specs/03-connection.md` — detailed unit specs for Phase 3
- `context/specs/04-execution.md` — detailed unit specs for Phase 4
