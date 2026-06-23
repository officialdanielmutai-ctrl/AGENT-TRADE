# Architecture Context

## The Three Layers

LEINTUM has three physical layers. Each has exactly one job. They
communicate in one direction through a fixed, versioned JSON
protocol. No layer does another layer's job.

```
MT5 EA  ──→  HTTP POST /heartbeat  ──→  Bridge  ──→  Claude API
        ←──  JSON decision          ←──         ←──  structured response

MT5 EA  ──→  HTTP POST /alert  ──→  Bridge  ──→  Claude API   (event-driven)
        ←──  JSON management  ←──          ←──  management response
```

Every call is logged: payload + response + timestamp + bar number.
Every decision is auditable. Every reasoning chain is stored.

| Layer | Name | Technology | Responsibility |
|---|---|---|---|
| L1 | The Scanner-Executor | MT5 / MQL5 | Connects to the broker. Fetches live OHLCV across all timeframes and instruments. Runs every formula module. Packages market state into a structured JSON payload. Sends it to the Bridge. Receives structured decisions back. Places, modifies, and closes orders. Enforces hard risk limits. **Never makes a trading decision.** |
| L2 | The Bridge | Node.js + Express | Receives payloads from the EA. Prepends the LEINTUM system prompt. Calls the LLM API with a timeout. Validates the structured response. Returns it to the EA. Logs every payload and decision. Handles fallback gracefully when the LLM is unreachable. **No market knowledge — pure transport and routing.** |
| L3 | The Intelligence Layer | Claude (Anthropic API) | Receives the structured market snapshot and the LEINTUM system prompt on every call. Reads bar anatomy, formula outputs, session context, macro calendar, open position state, and prior decision history. Reasons about the full picture. Produces a structured JSON decision: action, conviction, entry parameters, management instructions, and a full reasoning chain. **Never touches the market directly.** |

## Stack

| Layer | Technology | Version / Setting | Role |
|---|---|---|---|
| Trading platform | MetaTrader 5 | Build 4000+ | Broker connectivity, MQL5 execution, Strategy Tester for backtesting |
| EA language | MQL5 | C++ syntax subset | Native MT5 integration, `WebRequest` for HTTP, direct tick/order/history access |
| HTTP client (EA→Bridge) | MQL5 `WebRequest` | Built-in | Synchronous HTTP POST dispatch of JSON payloads |
| JSON serialisation (EA) | Manual string building | N/A | MQL5 has no native JSON library — `MarketStatePackager` builds JSON via string concatenation with validated, fixed field ordering |
| Timeframes | M1, M5, M15, M30, H1, H4, H12, D1 | — | M15 is the execution TF. M1/M5 are noise filters. H1/H4/D1 are context. H12/D1 are overextension checks |
| Correlated instruments | GBPUSD, USDCHF, USDJPY, AUDUSD, XAUUSD, USOIL | — | Weights: GBP +1.0, CHF −1.0, JPY −0.7, AUD +0.6, XAU +0.8, OIL −0.4 |
| HTTP server (Bridge) | Node.js + Express | Node 20 LTS, Express 4.x | Async-first, native JSON, minimal overhead, single-file deployable |
| LLM API client | Anthropic SDK for Node.js | `@anthropic-ai/sdk` latest | Official SDK — auth, retries, streaming |
| Request timeout | `AbortController` + `setTimeout` | Built-in | 8-second cap on LLM calls; fallback HOLD on timeout |
| Schema validation | Zod | `zod ^3.x` | Validates LLM JSON response before it reaches the EA; rejects malformed responses without crashing |
| Session logging | JSONL (jsonlines) | N/A | Append-only log, one JSON object per line — easy to grep/tail/parse |
| Process manager | PM2 | latest | Keeps the Bridge alive across restarts, auto-restart on crash, log rotation |
| Environment config | dotenv | `dotenv ^16` | API key, port, timeout, log path — never hardcoded |
| LLM provider | Anthropic Claude | current Sonnet release, read from `.env` | Fast (1–3s response), strong multi-layer market reasoning, cost-efficient at trading-session call volumes |
| Monitoring | Static HTML/JS + WebSocket | — | Session log viewer + live dashboard, no framework required |

> Model identifiers change over time. The Bridge must read the model
> name from `.env` (e.g. `LLM_MODEL=claude-sonnet-4-...`), never
> hardcode a literal model string in `llm.js`. Check current model
> names against Claude Platform docs before deploying.

## System Boundaries

```
leintum/
├── mt5/                              # Layer 1 — MQL5 source
│   ├── Experts/
│   │   └── LEINTUM_Engine.mq5        # Main EA file
│   └── Include/LEINTUMEngine/
│       ├── Defines.mqh               # All structs, enums, constants
│       ├── PriceFabric.mqh           # OHLCV fetcher for all TFs + instruments
│       ├── SessionProfile.mqh        # SVR + session state
│       ├── RegimeDetector.mqh        # DER + Hurst + RBE
│       ├── MomentumPhase.mqh         # NPV + IER + divergence + jerk
│       ├── ConditionAssessor.mqh     # VWAP + SDS + BQS
│       ├── ContextAnalyzer.mqh       # HTF flow velocity + consensus
│       ├── CorrelationMonitor.mqh    # Cross-pair energy field
│       ├── TradeHealthMonitor.mqh    # 5-component HealthScore
│       ├── MarketStatePackager.mqh   # JSON payload builder
│       ├── BridgeClient.mqh          # HTTP POST to Bridge
│       ├── DecisionExecutor.mqh      # LLM response parser + order placer
│       ├── EventTriggerMonitor.mqh   # Intra-bar watch conditions
│       └── RiskManager.mqh           # Hard limits + lot sizing
│
├── bridge/                           # Layer 2 — Node.js middleware
│   ├── server.js                     # Express server, main entry point
│   ├── llm.js                        # Anthropic API caller
│   ├── validator.js                  # Zod schema validation
│   ├── logger.js                     # JSONL session log writer
│   ├── fallback.js                   # HOLD response on LLM failure
│   ├── telegram.js                   # Trade/SPIKE/Bridge-down alerts
│   ├── system_prompt.txt             # Full LEINTUM system prompt
│   ├── .env                          # API key, port, config — gitignored
│   ├── package.json
│   └── ecosystem.config.js           # PM2 process config
│
├── dashboard/                        # Monitoring tools
│   ├── viewer.html                   # Session log viewer (standalone HTML)
│   ├── live.html                     # Live dashboard (WebSocket)
│   └── ws_server.js                  # WebSocket server for live dashboard
│
├── tools/                            # Dev and testing utilities
│   ├── prompt_tester.js              # Send sample payloads, inspect responses
│   ├── backtest_replay.py            # Replay historical payloads through the LLM
│   └── sample_payloads/              # Reference payload JSONs for testing
│
├── logs/                             # Runtime logs — gitignored
│   ├── session_YYYY-MM-DD.jsonl      # Daily session log
│   └── bridge.log                    # Bridge server log
│
└── context/                          # This six-file context system
    ├── project-overview.md, architecture.md, formulas.md,
    │   ui-context.md, code-standards.md, ai-workflow-rules.md,
    │   progress-tracker.md
    └── specs/                        # Build-unit spec files
```

`mt5/` owns sensing and execution. `bridge/` owns transport and
validation only — it must never contain market-interpretation logic.
`dashboard/` and `tools/` are read-only consumers of `logs/`.
`context/` is documentation, never application logic.

## Storage Model

- **Session logs (`logs/*.jsonl`)**: the system of record. Every
  heartbeat and alert payload, every LLM response, every reasoning
  chain, append-only, one line per call.
- **`.env` (Bridge)**: Anthropic API key, Bridge port, LLM timeout,
  LLM model name, log path, Telegram bot token/chat ID. Never
  committed, never hardcoded in source.
- **`bridge/system_prompt.txt`**: externalised system prompt, loaded
  at Bridge startup, version-controlled separately from code so it
  can be iterated without a redeploy.
- **No database.** LEINTUM is not a multi-user SaaS product — there
  is no Postgres/Prisma layer in this system. State (open positions,
  prior decision) lives in MT5's own position table and in the most
  recent log entries, not in a separate persistence layer.
- **`tools/sample_payloads/`**: static reference JSONs used for
  Bridge-isolation testing (Phase 1) and prompt regression testing.

## Auth and Access Model

- The Bridge authenticates to the Anthropic API using a single API
  key stored in `.env`. The key is never exposed to the EA or the
  dashboard.
- The EA authenticates to the broker via the MT5 terminal's own
  login session — not something this system manages.
- There is no end-user authentication layer. LEINTUM is operated by
  a single trader/operator — it is not a multi-tenant product, and
  access control concerns (user roles, ownership, RBAC) are
  explicitly out of scope.
- Telegram alerts authenticate via bot token; only the operator's
  chat ID receives notifications.

## Invariants

These are the rules the system must never violate. They are the
encoding of the governing trading principles validated in the live
one-week simulation.

1. **LLM decides, EA executes.** No trade opens, closes, or modifies
   without LLM authorisation, except the hard mechanical risk floor
   in `RiskManager.mqh` / `TradeHealthMonitor.mqh` (HealthScore < 25
   → immediate close, regardless of LLM reachability). The EA is
   hands, not brain.
2. **Formulas sense, the LLM reasons.** Every formula output becomes
   a labeled data point in the payload. Classification logic inside
   the MQL5 modules (e.g. `RegimeDetector`'s TRENDING/RANGING label)
   exists to inform the payload — it never gates execution on its own.
3. **Continuous awareness, never passive.** The LLM is called on
   every M15 bar and on any intra-bar event that trips a registered
   watch condition. There is no "set and forget" window.
4. **No fixed SL/TP by default.** `tp_basis: HOLD_MANAGED` is the
   default — exits are managed by reading the next bar, not a preset
   distance. Fixed-distance bases (`RR_1_5`, `RR_2_0`, etc.) are
   valid only as an explicit, reasoned LLM choice.
5. **Bar anatomy is primary.** Body size, wick location, volume
   relative to context, and session character outrank any single
   formula threshold when they conflict — encoded in system prompt
   §4 (management protocol) and tested directly in the benchmark
   replay (see `ai-workflow-rules.md`).
6. **Event intelligence.** The system does not trade within 2 hours
   of a tier-1 macro calendar release. This is a hard block at step 2
   of the decision protocol, before any formula state is considered.
7. **Conviction is bounded.** The EA will not execute a decision with
   conviction below 0.50. The LLM must never set conviction above
   0.90 — certainty above that level is itself a sign of
   miscalibration.
8. **Every composite score is clamped to its defined range before it
   reaches the payload.** The one-month backtest diagnostic found
   regime-strength values reporting far outside 0–100%, corrupting
   downstream confidence calculations — every module producing a
   normalised score (`strength`, `confidence`, `health_score`, etc.)
   must explicitly clamp output before storing or transmitting it.
9. **Schema is fixed and versioned.** Every JSON payload and response
   carries `schema_version`. A breaking change to shape requires a
   version bump, not a silent change — the Bridge's Zod validator and
   the EA's parser must be updated together.
