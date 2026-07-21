# System Prompt Iteration Notes

This document tracks major changes to the LLM system prompt (`bridge/system_prompt.txt`) throughout the project. 

## Phase 3.4 Iteration - Institutional Desk Model

**Date:** July 2026
**Issue:** The initial `system_prompt.txt` contained rigid, algorithmic kill-switches (e.g., "If H4 and D1 disagree with your intended direction, return HOLD"). This forced the LLM to behave like a standard Expert Advisor, preventing it from utilizing its holistic reasoning capabilities. It failed the benchmark bar (Tuesday 16:00 June 2) because it was forced to HOLD due to a HTF conflict, completely ignoring the clear price action distribution ceiling at 1.08522 (represented as 1.16522 in the EA test data).

**Changes Made:**
1. **Identity Update:** Re-cast LEINTUM as a "Head Analyst" synthesizing reports from different "desks" (Quant, Macro, Order Flow).
2. **Removed Kill Switches:** Replaced the rigid `agree_count` and conviction threshold gates with "Analytical Synthesis" guidelines.
3. **Price is Truth Override:** Explicitly instructed the LLM that clear Order Flow / Price Action structural setups override lagging HTF or Regime indicators.
4. **The Playbook:** Provided specific high-conviction setups to look for, explicitly outlining the "Distribution Top" (repeated tests of a ceiling + dropping volume) and "Accumulation Floor" setups to guide it toward recognizing textbook market structures.

**Result:**
The LLM is now empowered to make qualitative, analyst-style judgments when the quantitative data conflicts with clear structural price action.

---

## Phase 3.4 Iteration 2 - Prior Bar Memory

**Date:** July 2026
**Issue:** Even after the Institutional Analyst rewrite, the benchmark bar (35176) was still returning HOLD. Root cause: bar 35176 is a genuine doji in isolation — body_ratio 0.1818, near-equal wicks. The LLM was correct that a single doji is not a high-conviction sell. The Distribution Top signal only exists in the multi-bar context: bars 35172–35176 all tested the same ~1.16525 ceiling and were repeatedly rejected.

**Changes Made:**
1. **`tools/backtest_replay.py`** — Added a 5-bar rolling history buffer (`bar_history`). Before each POST to the bridge, the script injects `prior_bars` into the payload (slim OHLC + anatomy snapshot for the last 5 bars, oldest first).
2. **`bridge/system_prompt.txt`** — Added a new `PRIOR BAR CONTEXT (prior_bars)` section to the Measurement Framework. Instructed the LLM to scan `prior_bars` for repeated ceiling/floor tests. Upgraded the Distribution Top Playbook entry with explicit criteria: 3+ bars with similar highs (within ~5 pips), upper_wick_ratio > 0.25, body_ratio < 0.40, declining volume = OPEN_SELL regardless of HTF conflict.

**Expected Result:**
With prior_bars context, the LLM should now see bars 35172–35175 all tested ~1.16525 and were rejected. Bar 35176 (another doji at the same ceiling) should trigger the Distribution Top rule and return OPEN_SELL.

---

## Phase 3.5 Iteration 3 - Cooldown Rule (Prevent Over-triggering)

**Date:** July 2026
**Issue:** The Distribution Top rule triggered perfectly on the benchmark bar (35176), but it caused the LLM to over-trade significantly (87 trades in a week). Once a Distribution Top forms, every subsequent bar in the same zone looks like a Distribution Top.

**Changes Made:**
1. **`tools/backtest_replay.py`** — Added cooldown state tracking. Injects `cooldown: { active: bool, bars_since_last_trade: int, last_action: string }` into the payload. Cooldown is hardcoded to 12 bars (3 hours on M15).
2. **`bridge/system_prompt.txt`** — Added `COOLDOWN TRACKING (cooldown)` to the Measurement Framework. Added a new `HARD RISK RULE 4 (COOLDOWN GATE)`: "If cooldown.active is true, return HOLD."

**Expected Result:**
The system should still catch the benchmark +40 pip move on the initial signal, but then immediately enter a HOLD state for the next 12 bars, preventing the 30+ sequential stacked trades that were bleeding capital through tight stop-outs on minor pullbacks. Trade count should drop significantly to 10–20 per week.
