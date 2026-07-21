"""
weekly_pnl.py - Net P&L simulation for the July 18 session.
Uses the same SL logic as before, but instead of a fixed TP target,
exits open positions at end-of-week close price to get a true net pip figure.
"""
import json

SESSION_LOG  = 'logs/session_2026-07-21.jsonl'
PAYLOAD_FILE = 'payload_june.txt'

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
            bars[bn] = {
                'high':  cb.get('high'),
                'low':   cb.get('low'),
                'close': cb.get('close'),
            }
        except: continue

sorted_bars = sorted(bars.keys())
eow_close   = bars[max(sorted_bars)].get('close', 0)  # End-of-week close price

# ── 3. Simulate each trade — exit at SL or EOW close ─────────────────────────
results = []

for t in trades:
    bar_start = t['bar']
    action    = t['action']
    entry     = t['price']
    sl        = t['sl']
    sl_pips   = abs(entry - sl) * 10000

    exit_price  = None
    exit_reason = 'EOW'

    for b in sorted_bars:
        if b <= bar_start: continue
        hi = bars[b]['high']
        lo = bars[b]['low']
        if hi is None or lo is None: continue

        if action == 'OPEN_BUY':
            if lo <= sl:
                exit_price  = sl
                exit_reason = 'SL'
                break
        else:  # OPEN_SELL
            if hi >= sl:
                exit_price  = sl
                exit_reason = 'SL'
                break

    if exit_price is None:
        exit_price  = eow_close
        exit_reason = 'EOW'

    if action == 'OPEN_BUY':
        pnl = (exit_price - entry) * 10000
    else:
        pnl = (entry - exit_price) * 10000

    results.append({
        'bar':    bar_start,
        'action': action,
        'entry':  entry,
        'sl':     sl,
        'sl_pips': sl_pips,
        'exit':   exit_price,
        'reason': exit_reason,
        'pnl':    pnl,
    })

# ── 4. Print report ───────────────────────────────────────────────────────────
total_pnl  = sum(r['pnl'] for r in results)
win_rows   = [r for r in results if r['pnl'] > 0]
loss_rows  = [r for r in results if r['pnl'] <= 0]
gross_win  = sum(r['pnl'] for r in win_rows)
gross_loss = sum(r['pnl'] for r in loss_rows)
pf         = abs(gross_win / gross_loss) if gross_loss else float('inf')

print("=" * 72)
print("LEINTUM — Weekly Net P&L (June 1–5 2026, EOW exit at %.5f)" % eow_close)
print("=" * 72)
print()
print("  %-6s  %-9s  %-8s  %-7s  %-8s  %-4s  %s" % (
    "Bar", "Action", "Entry", "SL pip", "Exit", "How", "P&L (pips)"))
print("  " + "-" * 65)
for r in results:
    sign = "+" if r['pnl'] >= 0 else ""
    print("  %-6s  %-9s  %-8.5f  %-7.1f  %-8.5f  %-4s  %s%.1f" % (
        r['bar'], r['action'], r['entry'], r['sl_pips'],
        r['exit'], r['reason'], sign, r['pnl']))

print()
print("=" * 72)
print("NET WEEKLY P&L SUMMARY")
print("=" * 72)
print("  Trades                : %d" % len(results))
print("  Profitable trades     : %d  (%.0f%%)" % (len(win_rows),  100*len(win_rows)/len(results)  if results else 0))
print("  Loss-making trades    : %d  (%.0f%%)" % (len(loss_rows), 100*len(loss_rows)/len(results) if results else 0))
print()
print("  Gross profit          : +%.1f pips" % gross_win)
print("  Gross loss            : %.1f pips"  % gross_loss)
print("  NET P&L               : %+.1f pips" % total_pnl)
print("  Profit factor         : %.2f" % pf)
print()
if total_pnl > 0:
    print("  VERDICT: PROFITABLE WEEK  (+%.1f pips net)" % total_pnl)
else:
    print("  VERDICT: LOSING WEEK  (%.1f pips net)" % total_pnl)
print()
print("  Avg win               : +%.1f pips" % (gross_win /len(win_rows)  if win_rows  else 0))
print("  Avg loss              : %.1f pips"  % (gross_loss/len(loss_rows) if loss_rows else 0))
