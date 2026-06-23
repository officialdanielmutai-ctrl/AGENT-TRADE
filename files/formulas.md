# Formula Reference — The Sensing Layer

This is the indicator-free mathematics every MQL5 module implements.
The LLM reads these outputs — it does not compute them. No `iADX`,
`iBands`, `iATR`, `iMA`, `iRSI`, `iMACD`, or `iStochastic` calls exist
anywhere in this engine. Every signal is derived from raw OHLCV bars.

## Why indicators were replaced

| Original (indicator) | Problem |
|---|---|
| ADX (RegimeDetector) | Smoothed ratio of directional movement. Lags twice — once for TR averaging, once for DI smoothing. Reports trend strength as it was 14+ bars ago. |
| Bollinger Bands width (RegimeDetector) | Equal-weight variance treats a 3-pip tick the same as a 30-pip institutional bar. Cannot distinguish a quiet range from a slow trend. |
| ATR (RegimeDetector) | Spikes tell you a big bar happened, not why or in which direction. A volatile range and a breakout look identical. |
| RSI (MomentumPhase) | Mathematically equivalent to a ratio of two EMAs of returns. Overbought/oversold levels are arbitrary and timeframe-dependent. |
| MACD histogram (MomentumPhase) | Derivative of the difference between two EMAs — correlated with RSI by construction. Voting between them gives false confidence. |
| Stochastic (MomentumPhase) | A third correlated indicator built from the same close-series arithmetic as RSI and MACD. |
| EMA cross (ConditionAssessor) | Says nothing about structural displacement, auction zone, or bar quality — the things that actually define a setup. |
| Bollinger Bands for condition (ConditionAssessor) | Ignores volume entirely. High-volume institutional bars are treated identically to noise bars. |
| EMA + ADX + RSI on context TFs (ContextAnalyzer) | Same lag problems, just on slower timeframes. HTF structure is a geometric question, not an indicator-level one. |
| EMA + RSI on correlation pairs (CorrelationMonitor) | Asks only whether the average went up or down — not the energy or consistency of the move. |

## Shared utility — CPriceFabric

Pre-fetches all OHLCV arrays once per tick (200 bars × 8 timeframes)
and exposes them to every module, eliminating duplicate `CopyClose` /
`CopyHigh` calls and all indicator buffer overhead. All formula
functions accept a reference to `CPriceFabric` and a timeframe index
rather than calling `Copy*` themselves.

```
class CPriceFabric
{
   double  open[TF_COUNT][FABRIC_BARS];   // FABRIC_BARS = 200
   double  high[TF_COUNT][FABRIC_BARS];
   double  low[TF_COUNT][FABRIC_BARS];
   double  close[TF_COUNT][FABRIC_BARS];
   long    volume[TF_COUNT][FABRIC_BARS];
   bool    Refresh(string symbol);  // called once per OnTick, before any module Update()
}
```

---

## Module 1 — RegimeDetector

**Physical principle:** regime is a question about price geometry. A
trend covers net distance efficiently (low entropy). A range covers
distance inefficiently, visiting many zones with near-equal frequency
(high entropy).

**1.1 Directional Efficiency Ratio (DER)** — fraction of total path
length used for net displacement (N=20 recommended):
```
NetDisplacement = |close[1] - close[N]|
PathLength = Σ |close[i] - close[i+1]|  for i = 1..N-1
DER = NetDisplacement / PathLength      // 0.0–1.0, guard PathLength≈0 → DER=0
// >0.40 strong direction · 0.20–0.40 transition · <0.20 noise
```

**1.2 Hurst Exponent proxy (H)** — series memory via variance scaling
(n=8 recommended):
```
var_n  = Variance(returns, window=n)
var_2n = Variance(returns, window=2n)
H = log(var_2n / var_n) / (2 * log(2))   // var_n≈0 → H=0.5 (random walk)
// H>0.55 trending (persistent) · H<0.45 mean-reverting · 0.45–0.55 random walk
```

**1.3 Range Boundary Entropy (RBE)** — Shannon entropy over an
8-bucket histogram of bar midpoints (N=30):
```
Entropy = -Σ P(bucket_j) * ln(P(bucket_j))
NormEntropy = Entropy / ln(k)            // k=8 buckets
// <0.55 concentrated → RANGING · >0.75 spread → TRENDING
```

**1.4 Regime classification and exhaustion:**
```
RegimeScore = DER*0.45 + ((H-0.5)*2.0)*0.35 + (1.0-NBE)*0.20
if RegimeScore > 0.30:  regime = TRENDING (dir from net displacement sign)
                        strength = min(RegimeScore/0.60, 1.0)
elif RegimeScore < 0.10: regime = RANGING
                        strength = (0.10-RegimeScore)/0.10
else:                   regime = RANGING  // conservative transition zone
                        strength = 0.20

// Exhaustion — compare DER over two non-overlapping 5-bar windows
Deceleration = (DER_prior - DER_recent) / DER_prior   // guard DER_prior>0.05
if regime is TRENDING and Deceleration > 0.35:
    regime = RANGING; strength = 0.15   // suppress trend-following entries
```

**Output fields:** `regime` type, `strength` (clamped 0–1), `der`,
`hurst`, `boundary_entropy`, `deceleration` flag.

---

## Module 2 — MomentumPhase

**Physical principle:** momentum is kinematic. Velocity is the rate
of change of position; acceleration is the rate of change of
velocity. Waxing = positive acceleration in the move's direction.
Waning = negative. Exhausted = below noise floor or reversed.

**2.1 Normalised Price Velocity (NPV)** — median (not mean, for
spike robustness) of 1-bar returns, normalised by range (N_fast=5
M1/M5, 7 on M15):
```
NPV = Median(Returns[1..N_fast]) / Range_N    // typically [-1.0, +1.0]
// |NPV| > 0.30 → meaningful directional pressure
```

**2.2 Velocity Curvature / Acceleration** — NPV over two
non-overlapping 5-bar windows:
```
Acceleration = NPV_recent - NPV_prior
// Exhaustion: |NPV_recent|<0.10 AND sign(NPV_recent) != sign(NPV_prior)
```

**2.3 Impulse Energy Ratio (IER)** — recent burst energy vs. Median
Absolute Deviation noise floor (N_fast=5, N_long=30):
```
MAD_floor = Median(|Returns[1..N_long]|)
RecentEnergy = Σ |close[i]-close[i+1]|  for i=1..N_fast
IER = RecentEnergy / (N_fast * MAD_floor)
// >2.0 strong impulse · 1.0–2.0 moderate · <0.70 exhausted (quieter than its own noise floor)
```

**2.4 Bar-Energy Divergence** (replaces RSI divergence) — energy at
the two most recent swing lows/highs (5-bar window sum of |returns|
around each swing):
```
BullDiv = (low[sw1] < low[sw2]) AND (Energy_sw1 < Energy_sw2 * 0.85)
BearDiv = (high[sw1] > high[sw2]) AND (Energy_sw1 < Energy_sw2 * 0.85)
```

**2.5 Phase classification:**
```
movingUp/movingDn = NPV_recent ±0.05
WAXING:    IER>1.50 AND acceleration confirms direction → strength = min(IER/3.0, 1.0)
EXHAUSTED: IER<0.70 OR (BullDiv & movingDn) OR (BearDiv & movingUp) → strength = 0.90
WANING:    velocity in direction but decelerating → strength = 0.60 (+0.20 if divergence)
NEUTRAL:   else → strength = 0.30
```

---

## Module 3 — ConditionAssessor

**Physical principle:** fair value should be anchored by volume, not
a simple close-price average. Setups are a microstructure question —
displacement from structure, plus bar conviction.

**3.1 Volume-Weighted Value Area (VWAP ± σ)** (N=30):
```
VWAP = Σ(TypicalPrice_i * volume_i) / TotalVolume
VW_StdDev = sqrt(Σ volume_i*(TypicalPrice_i - VWAP)² / TotalVolume)
ValueAreaHigh = VWAP + VW_StdDev ; ValueAreaLow = VWAP - VW_StdDev
// inside → "in value" · outside → displaced · beyond ±2σ → highly extended
```

**3.2 Structural Displacement Score (SDS)** — displacement from prior
structure (bars 6–20, skipping the immediate 5 bars):
```
StructMid = (max(high[6..20]) + min(low[6..20])) / 2
SDS = (close[1] - StructMid) / (StructRange/2)
// +1.0 top of prior structure · -1.0 bottom · beyond ±1.0 = breakout from structure
InValue = -0.50 < SDS < 0.50
PriorDisplacedBull/Bear = PriorSDS (bars 11–25) > 0.40 / < -0.40
```

**3.3 Bar Quality Score (BQS)** (replaces Stochastic fallback):
```
BodyRatio = |Body| / TotalRange          // 0=doji, 1=marubozu
CloseRatio = distance of close from the bar's "wrong" extreme / TotalRange
BQS = BodyRatio*0.60 + CloseRatio*0.40
// 0.70–1.00 strong conviction · 0.40–0.70 moderate · <0.40 indecisive/wick-heavy
```

**3.4 Condition classification** (priority order):
1. `PULLBACK_ENTRY` — prior displacement + now in-value + BQS>0.55 + phase≠EXHAUSTED → confidence 0.70(+0.10 if WAXING)
2. `TREND_CONTINUATION` — |SDS|>0.60 + IER>1.20 + phase==WAXING → confidence 0.65+BQS*0.15
3. `BREAKOUT` — close beyond value area + IER>1.50 + phase==WAXING → confidence 0.60
4. `MEAN_REVERSION` — |SDS|>1.20 + phase==EXHAUSTED → confidence 0.50
5. Fallback — structural bias only (`SDS≥0`→BUY) → confidence 0.44

---

## Module 4 — ContextAnalyzer

**Physical principle:** context timeframes don't produce signals —
they produce a structural topology reading. Overextension is a
quantile question, not an RSI level.

**4.1 HTF Structural Bias** — run on M30/H1/H4/D1:
```
HTF_DER (same formula, N=20) + price-vs-50-bar-midpoint + swing structure (kept unchanged)
DER>0.25 + StructDir aligned + price on the right side of midpoint → bias=BUY/SELL, strength=min(DER*2.0, 0.80)
DER<0.15 → flat HTF → bias=WAIT, strength=0.15
else → conflicted/transition → bias=WAIT, strength=0.20
```
H4 receives 2x weight in aggregate consensus.

**4.2 Quantile Overextension** (D1 only, replaces RSI>70):
```
Build distribution of rolling 20-bar returns over 200 bars; take P10/P90
overextended = CumReturn_20 > P90  OR  < P10
// feeds m_bias.overextended — ALWAYS blocks trades when true
```

---

## Module 5 — CorrelationMonitor

**Physical principle:** currency markets share liquidity pools.
Genuine EUR weakness shows up as consistent directional geometry
across multiple correlated pairs, not just one EMA cross.

**5.1 Cross-Pair DER Consensus:**
```
Signal_i = pairNetDir_i * corrWeight_i * pairDER_i
ConsensusScore = Σ Signal_i / Σ |corrWeight_i|   // range -1..+1
ConsensusScore > +0.30 → BUY, confidence = min(score/0.80, 1.0)
ConsensusScore < -0.30 → SELL, confidence = min(-score/0.80, 1.0)
else → WAIT, confidence = 0.0
```
Weights: GBPUSD +1.0, USDCHF −1.0, USDJPY −0.7, AUDUSD +0.6, XAUUSD
+0.8, USOIL/UKOIL −0.4.

**5.2 Pair availability** — a pair is available if ≥25 bars can be
copied on M15; unavailable pairs are excluded from `TotalWeight`
(existing check logic, kept unchanged).

---

## Module 6 — DecisionEngine integration changes

**6.1 Replace the EMA alignment gate with an SDS directional gate:**
```
// REMOVE: block if emaFast/emaSlow direction disagrees with trade direction
// REPLACE WITH:
sdsOk = (direction==BUY) ? (sds > -0.30) : (sds < 0.30)
if (!sdsOk) { /* BLOCKED: SDS opposes direction */ }
```

**6.2 Regime–Momentum coherence bonus** (inserted after the
correlation adjustment, before the threshold check):
```
if regime is TRENDING:
    WAXING → +0.08   WANING → -0.05   EXHAUSTED → -0.12
elif regime is RANGING:
    WAXING → +0.04 (potential breakout)   EXHAUSTED → +0.06 (mean-reversion setup)
conf = clamp(conf + CoherenceBonus, 0.0, 1.0)   // always re-clamp after any bonus
```

---

## LEINTUM-specific additions (v4, beyond the EA-level overhaul above)

These extend the formula layer for the LLM-managed system —
documented in the Blueprint, not the original overhaul doc:

- **Session Velocity Ratio (SVR)** — current 4-bar range vs. median
  of the last 24 4-bar ranges. Classifies session state
  SPIKE/HOT/NORMAL/QUIET. SPIKE/QUIET is a hard entry block (decision
  protocol step 1). Feeds `slMultiplier` into `RiskManager`.
- **HTF Flow Velocity / Flow Score** — `DER × RecencyAmplifier` per
  H1/H4/D1, urgency-weighted into an aggregate consensus (H4 = 2x
  weight). Strong HTF opposition blocks entry.
- **Cross-Pair Energy Field** — per-pair short-window IER + DER +
  energy state classification (ACTIVE/COASTING/DEAD) with velocity
  reversal detection. DEAD pairs are excluded from consensus.
- **5-component HealthScore** (`TradeHealthMonitor`) — A (HTF flow) +
  B (correlation energy) + C (momentum) + D (velocity delta) + E
  (microstructure), 0–100 per open position. Score 60–100: trail
  stop above each bar's high/low. 25–59: tighten SL toward entry.
  Below 25: close at market immediately — this is a hard floor with
  no LLM override.

## Struct changes (Defines.mqh)

| Struct | Removed fields | Added fields |
|---|---|---|
| `RegimeResult` | `adxValue`, `plusDI`, `minusDI`, `bbWidth`, `bbWidthMA`, `adxROC`, `priceDistATR` | `derValue`, `hurstProxy`, `boundaryEntropy`, `derRecent`, `derPrior`, `deceleration` |
| `MomentumResult` | `rsiValue`, `macdHistogram`, `macdHistPrev`, `stochMain`, `stochSignal` | `normVelocity`, `acceleration`, `ierValue`, `swingEnergy1`, `swingEnergy2`, `bullishDivergence`, `bearishDivergence` (detection logic changes, bools kept) |
| `ConditionResult` | `emaFast`, `emaSlow`, `bbUpper`, `bbLower`, `bbMiddle` | `sds`, `vwap`, `valueAreaHigh`, `valueAreaLow`, `barQuality`, `inValue` |

All other fields, enums, and definitions in `Defines.mqh` remain
unchanged.
