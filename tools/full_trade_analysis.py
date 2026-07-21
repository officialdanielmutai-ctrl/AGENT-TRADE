"""
full_trade_analysis.py - Detailed P&L simulation for the July 18 session.
Loads trades from the session log, then walks forward through the payload
file to compute MFE (max profit reached), MAE (max adverse excursion),
and whether SL was hit before a meaningful profit level.
"""
import json

SESSION_LOG  = 'logs/session_2026-07-18.jsonl'
PAYLOAD_FILE = 'payload_june.txt'
PROFIT_TARGET_PIPS = 15   # pips we call "meaningful profit reached"

# ── 1. Load trades ────────────────────────────────────────────────────────────
trades = []
with open(SESSION_LOG, 'r', encoding='utf-8') as f:
    for line in f:
        if not line.strip(): continue
        try:
            entry = json.loads(line)
        except: continue
        if entry.get('fallback'): continue
        resp  = entry.get('response', {})
        action = resp.get('action')
        if action not in ('OPEN_BUY', 'OPEN_SELL'): continue
        ent = resp.get('entry') or {}
        price = ent.get('price')
        sl    = ent.get('sl')
        if not price or not sl: continue
        trades.append({
            'bar':    entry.get('bar_number'),
            'action': action,
            'price':  price,
            'sl':     sl,
        })

# ── 2. Load bar prices from payload ──────────────────────────────────────────
bars = {}
with open(PAYLOAD_FILE, 'r', encoding='utf-8') as f:
    for line in f:
        brace = line.find('{')
        if brace == -1: continue
        try:
            p = json.loads(line[brace:])
            bn = p.get('bar_number')
            cb = p.get('current_bar', {})
            bars[bn] = {'high': cb.get('high'), 'low': cb.get('low'), 'close': cb.get('close')}
        except: continue

sorted_bars = sorted(bars.keys())

# ── 3. Simulate each trade ────────────────────────────────────────────────────
wins  = []   # reached PROFIT_TARGET_PIPS before SL
losses = []  # SL hit before reaching PROFIT_TARGET_PIPS
open_positive = []  # never hit SL, ended in profit
open_negative = []  # never hit SL, ended at loss

rows = []

for t in trades:
    bar_start = t['bar']
    action    = t['action']
    entry     = t['price']
    sl        = t['sl']
    sl_pips   = abs(entry - sl) * 10000

    mfe = 0.0   # max pips in profit
    mae = 0.0   # max pips against (negative)
    outcome = 'OPEN'
    exit_pips = None

    for b in sorted_bars:
        if b <= bar_start: continue
        hi = bars[b]['high']
        lo = bars[b]['low']
        if hi is None or lo is None: continue

        if action == 'OPEN_BUY':
            pip_hi = (hi - entry) * 10000
            pip_lo = (lo - entry) * 10000
            mfe = max(mfe, pip_hi)
            mae = min(mae, pip_lo)
            if lo <= sl:
                outcome   = 'LOSS'
                exit_pips = (sl - entry) * 10000
                break
            if pip_hi >= PROFIT_TARGET_PIPS:
                outcome   = 'WIN'
                exit_pips = PROFIT_TARGET_PIPS
                break
        else:  # OPEN_SELL
            pip_lo = (entry - lo) * 10000
            pip_hi = (entry - hi) * 10000
            mfe = max(mfe, pip_lo)
            mae = min(mae, pip_hi)
            if hi >= sl:
                outcome   = 'LOSS'
                exit_pips = (entry - sl) * 10000  # negative
                break
            if pip_lo >= PROFIT_TARGET_PIPS:
                outcome   = 'WIN'
                exit_pips = PROFIT_TARGET_PIPS
                break

    # Classify open trades by their terminal MFE vs MAE
    if outcome == 'OPEN':
        close_price = bars.get(max(sorted_bars), {}).get('close')
        if close_price:
            final = (close_price - entry)*10000 if action=='OPEN_BUY' else (entry - close_price)*10000
        else:
            final = mfe + mae  # rough estimate
        if final >= 0:
            open_positive.append(t)
        else:
            open_negative.append(t)

    rows.append({
        'bar':      bar_start,
        'action':   action,
        'price':    entry,
        'sl':       sl,
        'sl_pips':  sl_pips,
        'mfe':      mfe,
        'mae':      mae,
        'outcome':  outcome,
    })
    if outcome == 'WIN':
        wins.append(mfe)
    elif outcome == 'LOSS':
        losses.append(mae)

# ── 4. Print report ───────────────────────────────────────────────────────────
total = len(rows)
n_wins  = len(wins)
n_loss  = len(losses)
n_open  = len(open_positive) + len(open_negative)

print("=" * 72)
print("LEINTUM Phase 3.4 — Full Trade Quality Report (June 1–5 2026 Replay)")
print("=" * 72)
print()
print("  %-6s  %-9s  %-8s  %-6s  %-8s  %-8s  %s" % (
    "Bar", "Action", "Entry", "SL pip", "MFE pip", "MAE pip", "Outcome"))
print("  " + "-"*68)
for r in rows:
    print("  %-6s  %-9s  %-8.5f  %-6.1f  %-8.1f  %-8.1f  %s" % (
        r['bar'], r['action'], r['price'], r['sl_pips'],
        r['mfe'], r['mae'], r['outcome']))

print()
print("=" * 72)
print("SUMMARY")
print("=" * 72)
print("  Total trades opened     : %d" % total)
print("  Wins (hit +%dpips first) : %d  (%.0f%%)" % (
    PROFIT_TARGET_PIPS, n_wins, 100*n_wins/total if total else 0))
print("  Losses (hit SL first)   : %d  (%.0f%%)" % (
    n_loss, 100*n_loss/total if total else 0))
print("  Still open (profitable) : %d" % len(open_positive))
print("  Still open (at loss)    : %d" % len(open_negative))
print()
if wins:
    print("  Avg MFE on winners      : +%.1f pips" % (sum(wins)/len(wins)))
if losses:
    print("  Avg MAE on losers       : %.1f pips" % (sum(losses)/len(losses)))

all_mfe = [r['mfe'] for r in rows]
all_mae = [r['mae'] for r in rows]
print("  Avg MFE across ALL trades: +%.1f pips" % (sum(all_mfe)/len(all_mfe) if all_mfe else 0))
print("  Avg MAE across ALL trades: %.1f pips" % (sum(all_mae)/len(all_mae) if all_mae else 0))
print()
# Profit potential ratio — trades that went at least 10 pips positive at any point
went_positive = [r for r in rows if r['mfe'] >= 10]
print("  Trades that reached +10 pips at some point: %d / %d  (%.0f%%)" % (
    len(went_positive), total, 100*len(went_positive)/total if total else 0))
went_positive5 = [r for r in rows if r['mfe'] >= 5]
print("  Trades that reached +5  pips at some point: %d / %d  (%.0f%%)" % (
    len(went_positive5), total, 100*len(went_positive5)/total if total else 0))
print()
print("  Breakdown by direction:")
buys  = [r for r in rows if r['action'] == 'OPEN_BUY']
sells = [r for r in rows if r['action'] == 'OPEN_SELL']
buy_wins  = [r for r in buys  if r['outcome'] == 'WIN']
sell_wins = [r for r in sells if r['outcome'] == 'WIN']
print("    BUY  trades: %d  |  Wins: %d  (%.0f%%)" % (
    len(buys),  len(buy_wins),  100*len(buy_wins)/len(buys)   if buys  else 0))
print("    SELL trades: %d  |  Wins: %d  (%.0f%%)" % (
    len(sells), len(sell_wins), 100*len(sell_wins)/len(sells) if sells else 0))
