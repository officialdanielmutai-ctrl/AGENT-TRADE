## LEINTUM — Application Building Context

LEINTUM is a three-layer, LLM-managed currency trading system for EURUSD: an
MQL5 EA (sensor + executor), a Node.js bridge (transport), and Claude
(the intelligence layer that makes every trading decision).

Read the following files in order before implementing or making any
architectural decision:

1. `context/project-overview.md` — what LEINTUM is, the governing
   trading philosophy, goals, scope, and success criteria
2. `context/architecture.md` — the three-layer system, stack, folder
   ownership, storage model, and invariants the system must never violate
3. `context/formulas.md` — the indicator-free mathematical formula
   reference (DER, Hurst, RBE, NPV, IER, SDS, VWAP, BQS, HTF flow,
   cross-pair energy, HealthScore) that every MQL5 module implements
4. `context/ui-context.md` — visual conventions for the monitoring
   dashboard and session log viewer
5. `context/code-standards.md` — MQL5, Node.js, and JSON protocol
   conventions
6. `context/ai-workflow-rules.md` — the six-phase build discipline,
   scoping rules, and verification gates
7. `context/progress-tracker.md` — current phase, completed work,
   open questions, and next steps
8. `context/specs/00-build-plan.md` — the full unit list in build
   order, then the individual phase spec file for whatever you are
   currently building

Update `context/progress-tracker.md` after each meaningful
implementation change.

If implementation changes the architecture, the formula math, the
JSON protocol schema, or the standards documented in the context
files, update the relevant file before continuing — do not let the
code and the documentation disagree.

**Non-negotiable system rule:** the EA never makes a trading
decision. It senses (formulas), transmits (JSON payload), and
executes (orders) exactly what the LLM authorises. If a unit of work
would have the EA decide anything beyond hard risk-limit enforcement,
stop and re-read `context/architecture.md` § Invariants.
