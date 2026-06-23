# LEINTUM — Trading Intelligence System

## Overview

LEINTUM is a live, actively managed currency trading system for
EURUSD. It is not an Expert Advisor in the traditional sense and not
a strategy coded into a fixed rule engine. It is a three-layer
intelligent organism: an MT5/MQL5 EA that senses the market and
executes orders, a lightweight Node.js bridge that relays state, and
Claude — sitting at the helm as the intelligence layer — which reads
the full picture and makes every trading decision in real time.

The governing insight: markets are complex adaptive systems, not
deterministic ones. Every rigid rule written to capture an edge
creates a new edge case the rule cannot handle. LEINTUM replaces
rule-following with reasoning — a system that can read bar anatomy,
weigh conflicting signals, understand session and macro context, and
decide the way a seasoned trading desk would, using the formula
layer as instrumentation (its senses) rather than as the decision
engine itself.

This was proven, not theorised: in a live one-week EURUSD simulation
acting as an LLM trading desk, three trades were taken with no fixed
stop-loss or take-profit — exits managed in real time by reading bar
anatomy. Result: 3 wins, 0 losses, +81.5 pips net, maximum drawdown
12.9 pips across the full week. This protocol is what the system is
built to execute at scale.

## Goals

1. Replace every lagging, indicator-based signal (ADX, Bollinger
   Bands, ATR, RSI, MACD, Stochastic, EMA cross) with indicator-free
   mathematics derived from raw OHLCV — direction, persistence,
   entropy, velocity, energy, and volume-weighted value.
2. Give an LLM continuous, structured awareness of the market — every
   M15 bar (heartbeat) and on any intra-bar event (alert) — so it is
   never reasoning from stale or partial information.
3. Remove fixed SL/TP as the default exit mechanism. Manage open
   positions through real-time bar-by-bar reasoning, bounded by hard
   mechanical risk floors (HealthScore, conviction threshold, spread
   and macro-calendar gates) that never depend on the LLM being
   reachable.
4. Make every decision auditable: every payload, every LLM response,
   and every reasoning chain logged to a persistent, append-only
   session record.
5. Ship through six sequential, independently testable build phases,
   each gated by a concrete "done when" condition, with Phase 4 as
   the non-negotiable quality gate before any live capital is risked.

## Core Operational Flow (the heartbeat cycle)

1. Every 15 minutes, on a new M15 bar, `PriceFabric.Refresh()` fetches
   fresh OHLCV across all 8 timeframes (M1, M5, M15, M30, H1, H4,
   H12, D1) and all 6 correlated instruments (GBPUSD, USDCHF, USDJPY,
   AUDUSD, XAUUSD, USOIL).
2. All formula modules run in sequence: SessionProfile →
   RegimeDetector → MomentumPhase → ConditionAssessor →
   ContextAnalyzer → CorrelationMonitor. Every output is stored.
3. `MarketStatePackager` serialises the full output into a labeled
   JSON payload, with detected signal conflicts explicitly flagged.
4. `CBridgeClient` POSTs the payload to the Bridge. The EA does not
   block — it keeps managing open positions on every tick while the
   call is in flight.
5. The Bridge prepends the LEINTUM system prompt and calls the Claude
   API (8-second timeout, fallback HOLD on failure or malformed
   response).
6. Claude reasons through the 7-step decision protocol and returns a
   structured JSON decision: action, conviction, entry parameters,
   management instructions, and a full reasoning chain.
7. The Bridge validates the response schema (Zod) and returns it to
   the EA.
8. `CDecisionExecutor` checks the conviction threshold, enforces hard
   risk limits, maps instructions to exact order parameters, and
   places, modifies, or closes orders.
9. Between heartbeats, `EventTriggerMonitor` watches registered
   conditions on every tick (HealthScore drops, regime changes,
   correlated-pair energy flips, profit milestones) and fires a
   targeted, lower-weight management alert immediately when one
   trips — it does not wait for the next bar close.

## Features

### Sensing (MQL5 formula layer)
- RegimeDetector — Directional Efficiency Ratio, Hurst proxy, Range
  Boundary Entropy, exhaustion-by-deceleration
- MomentumPhase — Normalised Price Velocity, acceleration, Impulse
  Energy Ratio, bar-energy divergence
- ConditionAssessor — volume-weighted VWAP value area, Structural
  Displacement Score, Bar Quality Score
- ContextAnalyzer — higher-timeframe structural bias, D1 quantile
  overextension
- CorrelationMonitor — cross-pair DER consensus, energy-state
  classification, velocity reversal detection
- SessionProfile — Session Velocity Ratio (entry gate)
- TradeHealthMonitor — 5-component HealthScore per open position

### Transport (Node.js bridge)
- `/heartbeat`, `/alert`, `/status` endpoints
- LLM call wrapper with timeout and fallback HOLD
- Zod schema validation of every LLM response
- Append-only JSONL session logging
- PM2 process management, `.env`-driven configuration

### Intelligence (Claude)
- 5-section system prompt: identity, measurement framework, decision
  protocol, management protocol, response schema
- Structured JSON-only output, validated before reaching the EA
- Full natural-language reasoning chain stored alongside every decision

### Monitoring
- Static session log viewer (reads JSONL, colour-codes by outcome)
- Live WebSocket dashboard (current HealthScore, session state, last
  decision, open positions)
- Telegram alerts on trade open/close, SPIKE state, Bridge downtime

## Scope

### In Scope
- EURUSD as the traded instrument, with 6 correlated instruments used
  only for confirmation signal
- The full indicator-free formula layer (v4 / LEINTUM formula set)
- The 13 MQL5 modules, the Node.js bridge, and the JSON protocol v1.0
  exactly as specified in `architecture.md` and `formulas.md`
- Demo-account forward testing before any live deployment
- Session logging, log viewer, live dashboard, Telegram alerts

### Out of Scope
- Any instrument other than EURUSD as the primary traded pair
- Any decision logic living inside the EA beyond hard risk-limit
  enforcement — the EA never decides, only senses and executes
- A persistent database — the system is file/log based (JSONL), not
  a multi-user SaaS product
- Multi-account or multi-broker orchestration
- Fixed SL/TP as a default exit mechanism (HOLD_MANAGED is the
  default `tp_basis`; fixed bases exist only as explicit LLM choices)
- A polished, public-facing UI — the dashboard is an internal
  monitoring tool, not a product surface

## Success Criteria

1. All 13 MQL5 modules compile and produce correct, clamped output on
   historical Strategy Tester data (the regime-strength clamping bug
   found in the one-month backtest must not recur).
2. The Bridge responds to `/heartbeat` and `/alert` with a
   schema-valid decision in under 8 seconds, falling back to HOLD on
   any failure, with zero unhandled exceptions across a 10-day demo run.
3. On the June 1–5 2026 replay, Claude's decisions align with the
   documented professional-desk benchmark: no BUY on Tuesday morning,
   SELL entered Tuesday afternoon, LONG on the Thursday bear trap,
   SELL post-NFP.
4. A demo-account forward test of at least 2 weeks shows max drawdown
   under 20 pips per trade, 1–3 trades per day on average, and
   acceptable reasoning quality on more than 85% of logged decisions.
5. Every decision — payload, response, and reasoning — is present in
   the session log and reviewable end to end in under 5 minutes via
   the log viewer.
