"""
full_analysis.py - Full trade analysis for any session log.
Usage: python tools/full_analysis.py logs/session_2026-07-22.jsonl
"""
import json
import sys

SESSION_LOG  = sys.argv[1] if len(sys.argv) > 1 else 'logs/session_2026-07-22.jsonl'
PAYLOAD_FILE = 'payload_june.txt'
TP_PIPS      = 15

# ── 1. Load trades from session log ──────────────────────────────────────────
all_entries = []
fallback_count = 0
total_count = 0

with open(SESSION_LOG, 'r', encoding='utf-8') as f:
    for line in f:
        if not line.strip(): continue
        try:
            entry = json.loads(line)
        except: continue
        total_count += 1
        if entry.get('fallback'):
            fallback_count += 1
            continue
        all_entries.append(entry)

trades = []
holds  = 0
for entry in all_entries:
    resp   = entry.get('response', {})
    action = resp.get('action', 'HOLD')
    bar_num = entry.get('bar_number')
    if action in ('OPEN_BUY', 'OPEN_SELL'):
        ent = resp.get('entry') or {}
        price = ent.get('price')
        sl    = ent.get('sl')
        if price and sl:
            trades.append({
                'bar':     bar_num,
                'action':  action,
                'price':   price,
                'sl':      sl,
                'sl_pips': abs(price - sl) * 10000,
                'summary': resp.get('reasoning', {}).get('summary', '')[:90],
            })
    else:
        holds += 1

# ── 2. Load bar OHLC from payload file ───────────────────────────────────────
bars = {}
with open(PAYLOAD_FILE, 'r', encoding='utf-8') as f:
    for line in f:
        brace = line.find('{')
        if brace == -1: continue
        try:
            p  = json.loads(line[brace:])
            bn = p.get('bar_number')
            cb = p.get('current_bar', {})
            bars[bn] = {
                'high':  cb.get('high'),
                'low':   cb.get('low'),
                'close': cb.get('close'),
            }
        except: continue

sorted_bars = sorted(bars.keys())
eow_close   = bars[max(sorted_bars)].get('close', 0)

# ── 3. Simulate each trade ────────────────────────────────────────────────────
rows = []
for t in trades:
    bar_start = t['bar']
    action    = t['action']
    price     = t['price']
    sl        = t['sl']

    mfe        = 0.0
    mae        = 0.0
    tp_outcome = None
    sl_outcome = None
    eow_pnl    = None

    for b in sorted_bars:
        if b <= bar_start: continue
        hi = bars[b]['high']
        lo = bars[b]['low']
        if hi is None or lo is None: continue

        if action == 'OPEN_BUY':
            mfe = max(mfe, (hi - price) * 10000)
            mae = min(mae, (lo - price) * 10000)
            if tp_outcome is None and (hi - price) * 10000 >= TP_PIPS:
                tp_outcome = TP_PIPS
            if sl_outcome is None and lo <= sl:
                sl_outcome = (sl - price) * 10000
        else:
            mfe = max(mfe, (price - lo) * 10000)
            mae = min(mae, (price - hi) * 10000)
            if tp_outcome is None and (price - lo) * 10000 >= TP_PIPS:
                tp_outcome = TP_PIPS
            if sl_outcome is None and hi >= sl:
                sl_outcome = (price - sl) * 10000

    # Determine what hit first
    if tp_outcome is not None and sl_outcome is not None:
        # need to replay bar-by-bar to see which hit first
        result_pips = None
        result_how  = None
        for b in sorted_bars:
            if b <= bar_start: continue
            hi = bars[b]['high']
            lo = bars[b]['low']
            if hi is None or lo is None: continue
            if action == 'OPEN_BUY':
                if lo <= sl:
                    result_pips = sl_outcome
                    result_how  = 'SL'
                    break
                if (hi - price)*10000 >= TP_PIPS:
                    result_pips = TP_PIPS
                    result_how  = 'TP'
                    break
            else:
                if hi >= sl:
                    result_pips = sl_outcome
                    result_how  = 'SL'
                    break
                if (price - lo)*10000 >= TP_PIPS:
                    result_pips = TP_PIPS
                    result_how  = 'TP'
                    break
    elif tp_outcome is not None:
        result_pips = TP_PIPS
        result_how  = 'TP'
    elif sl_outcome is not None:
        result_pips = sl_outcome
        result_how  = 'SL'
    else:
        # EOW exit
        if action == 'OPEN_BUY':
            result_pips = (eow_close - price) * 10000
        else:
            result_pips = (price - eow_close) * 10000
        result_how = 'EOW'

    rows.append({
        'bar':     bar_start,
        'action':  action,
        'price':   price,
        'sl_pips': t['sl_pips'],
        'mfe':     mfe,
        'mae':     mae,
        'pnl':     result_pips,
        'how':     result_how,
        'summary': t['summary'],
    })

# ── 4. Report ─────────────────────────────────────────────────────────────────
wins   = [r for r in rows if r['pnl'] > 0]
losses = [r for r in rows if r['pnl'] < 0]
flat   = [r for r in rows if r['pnl'] == 0]
gross_w = sum(r['pnl'] for r in wins)
gross_l = sum(r['pnl'] for r in losses)
net     = gross_w + gross_l
pf      = abs(gross_w / gross_l) if gross_l else float('inf')
all_mfe = [r['mfe'] for r in rows]
all_mae = [r['mae'] for r in rows]
sl_pips = [r['sl_pips'] for r in rows]

print("=" * 72)
print("LEINTUM Phase 3.5 — Trade Report  (Cooldown = 12 bars / 3h)")
print("Session: %s   EOW close: %.5f" % (SESSION_LOG, eow_close))
print("=" * 72)
print()
print("  %-6s  %-9s  %-8s  %-6s  %-8s  %-8s  %-5s  %s" % (
    "Bar", "Action", "Entry", "SL pip", "MFE pip", "MAE pip", "How", "P&L"))
print("  " + "-" * 68)
for r in rows:
    sign = "+" if r['pnl'] >= 0 else ""
    print("  %-6s  %-9s  %-8.5f  %-6.1f  %-8.1f  %-8.1f  %-5s  %s%.1f" % (
        r['bar'], r['action'], r['price'], r['sl_pips'],
        r['mfe'], r['mae'], r['how'], sign, r['pnl']))

print()
print("=" * 72)
print("SUMMARY")
print("=" * 72)
print("  Total bars processed      : %d" % total_count)
print("  Fallbacks                 : %d" % fallback_count)
print("  HOLDs                     : %d" % holds)
print("  Trades opened             : %d" % len(rows))
print()
print("  Wins  (hit +%d pips)       : %d  (%.0f%%)" % (
    TP_PIPS, len(wins), 100*len(wins)/len(rows) if rows else 0))
print("  Losses (hit SL)           : %d  (%.0f%%)" % (
    len(losses), 100*len(losses)/len(rows) if rows else 0))
print("  EOW flat                  : %d" % len(flat))
print()
print("  Gross profit              : %+.1f pips" % gross_w)
print("  Gross loss                :  %.1f pips" % gross_l)
print("  NET P&L                   : %+.1f pips" % net)
print("  Profit factor             :  %.2f" % pf)
print()
print("  Avg win                   : %+.1f pips" % (gross_w/len(wins)    if wins   else 0))
print("  Avg loss                  :  %.1f pips" % (gross_l/len(losses)  if losses else 0))
print("  Avg MFE (all trades)      : %+.1f pips" % (sum(all_mfe)/len(all_mfe) if all_mfe else 0))
print("  Avg MAE / drawdown        :  %.1f pips" % (sum(all_mae)/len(all_mae) if all_mae else 0))
print("  Avg SL size               :  %.1f pips" % (sum(sl_pips)/len(sl_pips) if sl_pips else 0))
print()
print("  Trades reaching +10 pips  : %d / %d  (%.0f%%)" % (
    sum(1 for r in rows if r['mfe'] >= 10), len(rows),
    100*sum(1 for r in rows if r['mfe'] >= 10)/len(rows) if rows else 0))
print("  Trades reaching +5 pips   : %d / %d  (%.0f%%)" % (
    sum(1 for r in rows if r['mfe'] >= 5), len(rows),
    100*sum(1 for r in rows if r['mfe'] >= 5)/len(rows) if rows else 0))
print()
buys  = [r for r in rows if r['action'] == 'OPEN_BUY']
sells = [r for r in rows if r['action'] == 'OPEN_SELL']
print("  BUY  trades: %-3d  Wins: %-3d  (%.0f%%)" % (
    len(buys),  sum(1 for r in buys  if r['pnl']>0), 100*sum(1 for r in buys  if r['pnl']>0)/len(buys)  if buys  else 0))
print("  SELL trades: %-3d  Wins: %-3d  (%.0f%%)" % (
    len(sells), sum(1 for r in sells if r['pnl']>0), 100*sum(1 for r in sells if r['pnl']>0)/len(sells) if sells else 0))
print()
if net > 0:
    print("  VERDICT: PROFITABLE  (%+.1f pips net)" % net)
else:
    print("  VERDICT: LOSING  (%.1f pips net)" % net)
