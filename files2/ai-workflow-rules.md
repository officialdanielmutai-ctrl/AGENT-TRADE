# AI Workflow Rules

## The Build Discipline

LEINTUM is built in six sequential phases. Each phase has a concrete
"done when" condition. No phase begins until the previous phase's
condition is met. This is not a suggestion — skipping a phase gate
means building execution logic on top of unvalidated sensing logic,
which produces a system that looks complete but fails in live trading.

```
Phase 1 — Bridge in isolation (no MT5)
Phase 2 — MT5 formula layer (no Bridge calls, no execution)
Phase 3 — MT5 → Bridge connected (payloads flowing, no execution)
Phase 4 — Execution layer + event system (full loop, demo sizing)
Phase 5 — Demo account forward test (2 weeks, real market)
Phase 6 — Live deployment
```

Each phase spec lives in `context/specs/` as a numbered file:
`01-bridge.md`, `02-mt5-formulas.md`, etc.

---

## Aider Prompting Rules

These rules apply to every Aider session. They are derived from what
worked in Hisaflow development and adapted for the LEINTUM stack.

### 1. Always scope to a single unit of work

One prompt = one file or one tightly coupled pair of files. Never ask
Aider to implement multiple modules in one prompt.

```
# Correct
"Implement logger.js — the JSONL append writer as specified in
context/code-standards.md. File: bridge/logger.js. Say done when finished."

# Wrong
"Implement the full bridge layer"
```

### 2. Always specify the file list explicitly

Start every prompt with the files Aider should read and the file it
should write. This prevents Aider from touching files it shouldn't.

```
Read: context/architecture.md, context/code-standards.md
Write: bridge/logger.js
Do not touch any other file.
```

### 3. Surgical change instructions

Describe what to implement, not how to structure the entire codebase.
Reference the spec and let the spec carry the detail.

```
# Correct
"Implement the Zod schema in validator.js matching the response schema
in Section 8.2 of the blueprint. All five valid action values must be
enumerated. Say done when finished."

# Wrong
"Make validator.js better and also check if server.js needs updating"
```

### 4. Always end with a terminator

End every Aider prompt with: `Say done when finished.`
This prevents Aider from continuing to generate beyond the scope.

### 5. Never ask Aider to make architectural decisions

If a prompt requires Aider to choose between two approaches not
specified in the context files, stop. Make the decision yourself,
update the relevant context file, then prompt Aider to implement the
now-specified approach.

### 6. After each unit: verify before continuing

Run the "done when" check from the phase spec before starting the
next unit. Do not stack multiple unverified units.

---

## Phase Gate Verification Checklist

### Phase 1 Gate (Bridge isolation)
- [ ] `node bridge/server.js` starts without error
- [ ] `curl http://localhost:3001/status` returns `{"ok":true}`
- [ ] `node tools/prompt_tester.js` with 5 sample payloads returns
      schema-valid responses (check with validator.js manually)
- [ ] All 5 responses have coherent reasoning chains (read them)
- [ ] Session log file created in `logs/` with correct JSONL format
- [ ] Fallback HOLD fires when ANTHROPIC_API_KEY is set to an invalid value

### Phase 2 Gate (MT5 formula layer)
- [ ] All 13 `.mqh` files compile in MetaEditor with zero errors
- [ ] Strategy Tester run on any 1-week period shows correct
      regime/momentum/session output in Expert log
- [ ] Regime strength values are always in [0, 1] — check 100 bars
- [ ] HealthScore values are always in [0, 100]
- [ ] `Print()` of a serialised payload passes jsonlint.com validation
- [ ] Macro calendar field present and accurate in payload

### Phase 3 Gate (connected, no execution)
- [ ] EA sends payload to Bridge on each M15 bar close
- [ ] Bridge prints received payload to console (confirm shape)
- [ ] LLM decision printed to MT5 Expert log — NOT executed
- [ ] June 1–5 2026 replay: LLM decisions match the benchmark
      (no BUY Tuesday morning, SELL Tuesday afternoon, LONG Thursday
      bear trap, SELL post-NFP)
- [ ] System prompt version documented in `docs/SYSTEM_PROMPT_NOTES.md`

### Phase 4 Gate (full execution loop)
- [ ] OPEN_SELL with conviction 0.82 places a market SELL order
- [ ] OPEN_BUY with conviction 0.42 is rejected and logged
- [ ] Spread > limit blocks entry and logs the rejection
- [ ] HealthScore < 25 on a demo position triggers market close
      without waiting for next heartbeat
- [ ] EventTriggerMonitor fires REGIME_CHANGE alert intra-bar
- [ ] Telegram notification received within 5s of trade open

### Phase 5 Gate (demo forward test)
- [ ] 10 consecutive trading days with no Bridge crash or unhandled
      exception
- [ ] Max drawdown < 20 pips on any single trade
- [ ] Reasoning quality acceptable on > 85% of reviewed decisions
- [ ] Fallback stress test: Bridge disconnected mid-session, fallback
      HOLD fires, Bridge reconnects, resumes on next bar

---

## The Benchmark Replay Test

This is the single most important quality gate in the entire build.
It must be run at the end of Phase 3 and again after any meaningful
system prompt change.

**The test:** Send the LLM the Tuesday 16:00 June 2 2026 payload —
the bar where four failed tests of 1.08522 were followed by a
distribution break on volume drop.

**Ask:** "What do you see? What would you do?"

**Pass condition:** The response mentions:
- The distribution ceiling at 1.08522
- The volume character (drop on the break attempt)
- The failed bullish tests (bar anatomy, not just DER)
- Recommends SELL with `tp_basis: HOLD_MANAGED`

**Fail condition:** The response fires a BUY based on the DER reading
alone, ignores bar anatomy, or does not mention volume character.

A fail means the system prompt needs another iteration. Document
every iteration and what changed in `docs/SYSTEM_PROMPT_NOTES.md`.

---

## What to Update After Each Session

After every meaningful implementation session, update
`context/progress-tracker.md` with:
1. What was completed (file name + phase step number)
2. The "done when" condition and whether it passed
3. Any open questions or deferred issues
4. The next step

If implementation changes the architecture, the formula math, the
JSON protocol schema, or the standards in the context files — update
the relevant context file before continuing. The code and the
documentation must never disagree.

---

## Scope Boundaries for the AI

The AI (Aider/Claude) must never:
- Add a database or ORM layer (no Postgres, no Prisma, no SQLite)
- Add a frontend framework to the dashboard files (no React, no Vue)
- Add multi-instrument trading logic (EURUSD only)
- Move decision logic into the EA beyond hard risk-limit enforcement
- Add user authentication or multi-user concepts
- Silently change the JSON schema without updating `validator.js`
  and `Defines.mqh` together

If a prompt would cause any of the above, the AI must stop and flag
it rather than implement it.
