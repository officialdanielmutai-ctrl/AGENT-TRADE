# Code Standards

## MQL5 (Layer 1 — MT5 EA)

### File organisation
- One class per `.mqh` file. Class name matches file name exactly.
- All structs, enums, and constants live in `Defines.mqh` — never
  scatter them across module files.
- `LEINTUM_Engine.mq5` is the orchestrator only: it calls module
  methods in the correct sequence and nothing else. No formula logic
  inside the main EA file.

### Naming
- Classes: `PascalCase` — `RegimeDetector`, `MarketStatePackager`
- Methods: `PascalCase` — `Refresh()`, `Compute()`, `Serialize()`
- Member variables: `m_` prefix, camelCase — `m_derValue`, `m_regimeStrength`
- Constants / enums: `SCREAMING_SNAKE_CASE` — `SESSION_SPIKE`, `PHASE_WAXING`
- Local variables: camelCase — `barRange`, `velocityDelta`

### Clamping — non-negotiable
Every module that produces a normalised score must clamp before
storing or returning. No exceptions. The one-month backtest found
regime-strength values far outside 0–1, corrupting downstream
calculations. Every such value must be clamped at the point of
assignment:

```mql5
// Correct
m_regimeStrength = MathMax(0.0, MathMin(1.0, rawStrength));

// Wrong — never store unclamped
m_regimeStrength = rawStrength;
```

Applies to: `regime_strength`, `confidence`, `health_score`,
`conviction`, `flow_score`, `consensus_score`, `der`, `hurst`,
`ier`, `npv`, `bqs`, `sds`. If you add a new normalised field,
clamp it.

### JSON serialisation
MQL5 has no native JSON library. `MarketStatePackager` builds JSON
via string concatenation. Rules:
- Always use `StringFormat()` for numeric fields — never rely on
  implicit double-to-string conversion.
- Fixed field ordering within each object — do not reorder fields
  between builds. The Bridge's Zod validator expects a consistent
  schema.
- Escape all string values: replace `"` with `\"` before
  interpolating into JSON strings.
- After building a payload, `Print()` it and verify with
  jsonlint.com before the first Bridge connection.

### WebRequest usage
- `CBridgeClient` is the only file that calls `WebRequest`. No other
  module makes HTTP calls.
- Always check the return value. On non-200 or timeout, log the
  error and return the fallback HOLD struct — never leave
  `CDecisionExecutor` with an uninitialised response.
- The EA does not block on the HTTP call for position management —
  tick processing continues while the call is in flight. Implement
  this with the async pattern documented in `BridgeClient.mqh`.

### Hard limits — always enforced by RiskManager, never bypassed
- Conviction < 0.50 → reject, log, do not execute.
- Spread > configured limit → reject entry, log.
- HealthScore < 25 → emergency close, regardless of LLM reachability.
- Max open positions: 1 (EURUSD only).
- Daily loss limit: configurable in `.env`, enforced in `RiskManager`.

### Print / logging
- Use `PrintFormat()` for structured log lines, not `Print()` with
  string concatenation.
- Prefix all EA log lines with `[LEINTUM]` for easy filtering in the
  MT5 Expert log.
- Log level: INFO for normal flow, WARN for rejected decisions,
  ERROR for WebRequest failures or schema violations.

---

## Node.js (Layer 2 — Bridge)

### Runtime
- Node.js 20 LTS. No TypeScript — plain JS with JSDoc comments where
  the shape of an object needs to be documented.
- ES modules (`"type": "module"` in `package.json`). Use `import`/
  `export`, not `require`.
- All async functions use `async`/`await`. No raw Promise chains
  except where the library forces it.

### File responsibilities — strict separation
| File | Owns | Must never contain |
|---|---|---|
| `server.js` | Express setup, route handlers, startup | LLM call logic, market interpretation |
| `llm.js` | Anthropic SDK call, timeout, fallback | Route logic, Zod validation |
| `validator.js` | Zod schema definition and `parse()` call | Any LLM or logging logic |
| `logger.js` | JSONL append writer | Any business logic |
| `fallback.js` | Static HOLD response constructor | Any LLM or network logic |
| `telegram.js` | Telegram Bot API calls | Any trading or routing logic |
| `ws_server.js` | WebSocket server, state broadcast | Any LLM or file logic |

### Error handling
- Every route handler wrapped in try/catch. On any unhandled error,
  return the fallback HOLD response to the EA — never let the EA
  hang waiting for a response that never comes.
- `llm.js` must handle three failure modes explicitly:
  1. LLM API timeout (> 8s) → fallback HOLD
  2. Malformed JSON in response → fallback HOLD
  3. Zod validation failure → fallback HOLD
- Log every failure with `console.error` before returning fallback.
  The session log must record fallback responses with
  `"fallback": true` so the operator can see when the LLM was
  unreachable.

### Environment config
- All config in `.env`. Load with `dotenv` at Bridge startup.
- Required keys: `ANTHROPIC_API_KEY`, `BRIDGE_PORT`, `LLM_MODEL`,
  `LLM_TIMEOUT_MS`, `LOG_PATH`, `TELEGRAM_BOT_TOKEN`,
  `TELEGRAM_CHAT_ID`.
- `LLM_MODEL` is read from `.env` at runtime — the model string is
  never hardcoded in `llm.js`. This allows model updates without a
  code change.
- `.env` is gitignored. Provide `.env.example` with all keys and
  placeholder values.

### Zod schema
The Zod schema in `validator.js` is the contract between the LLM and
the EA. It must match the response schema in Section 8.2 of the
blueprint exactly. When the schema changes, bump `schema_version` in
both the Zod schema and the MQL5 parser, and update this file.

Current required top-level fields:
`decision_type`, `schema_version`, `bar_number`, `action`, `entry`,
`management`, `reasoning`, `watch`

Valid `action` values: `OPEN_BUY`, `OPEN_SELL`, `HOLD`,
`CLOSE_ALL`, `CLOSE_PARTIAL`

### Session logging
- Every call (heartbeat and alert) appended to
  `logs/session_YYYY-MM-DD.jsonl` as a single JSON line.
- Each log entry shape:
```json
{
  "ts": "2026-06-09T09:15:00.000Z",
  "type": "heartbeat",
  "bar_number": 847,
  "fallback": false,
  "payload": { ...full EA payload... },
  "response": { ...full LLM response... },
  "latency_ms": 1420
}
```
- `logger.js` must never throw — wrap the `fs.appendFile` call in
  try/catch and swallow logging errors silently (a log failure must
  not crash the Bridge or delay the response to the EA).

### PM2
- `ecosystem.config.js` defines one app: `leintum-bridge`.
- `watch: false` — PM2 must not restart on file changes in
  production (log files change constantly).
- `max_memory_restart: '200M'`.
- Log files: `./logs/bridge.log` (stdout + stderr merged).

---

## JSON Protocol

- Schema version: `"1.0"` for all current payloads and responses.
- Payload built by `MarketStatePackager.mqh`, consumed by the Bridge.
- Response built by the LLM, validated by `validator.js`, consumed
  by `DecisionExecutor.mqh`.
- Breaking changes (field removal, type change, required field added)
  require a version bump to `"1.1"` and coordinated updates to both
  `validator.js` and the MQL5 parser before deployment.
- Additive changes (new optional field) do not require a version bump
  but must be documented here.

**Additive change — current_bar payload block (schema v1.0, unchanged):**
`open`, `high`, `low`, `close` (float, 5 d.p.) added to the
`current_bar` JSON object in `MarketStatePackager.mqh`. Field ordering:
raw OHLC prices first, then `body_ratio`, `upper_wick_ratio`,
`lower_wick_ratio`, `volume`, `volume_avg`. The `SBarAnatomy` struct
in `Defines.mqh` already declared these fields — the Packager was
simply not serialising them, causing the LLM to hallucinate entry
prices. This is an additive change: `validator.js` validates the LLM
response (not the MT5 payload) and is unchanged.

---

## Git

- Commit style: `layer: short description`
  Examples: `bridge: add zod validation for alert response`
           `mt5: implement RegimeDetector clamping fix`
           `prompt: tighten bar anatomy section`
           `context: update progress tracker to phase 2`
- Branch per phase: `phase-1-bridge`, `phase-2-mt5`, etc.
- Never commit `.env`, `logs/`, or `node_modules/`.
- Commit `system_prompt.txt` with every meaningful change — it is a
  versioned artifact, not a config file.
