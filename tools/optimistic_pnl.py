"""
optimistic_pnl.py - Net P&L using a fixed +15 pip TP.
For each trade: if it reached +15 pips before SL was hit, book +15 pips.
If SL was hit first, book the SL loss. This represents the scenario where
a management layer (or the LLM itself) would have closed at that profit level.
"""
import json

SESSION_LOG  = 'logs/session_2026-07-21.jsonl'
PAYLOAD_FILE = 'payload_june.txt'
TP_PIPS      = 15   # fixed take-profit target in pips

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

# ── 2. Load bar prices ────────────────────────────────────────────────────────
bars = {}
with open(PAYLOAD_FILE, 'r', encoding='utf-8') as f:
    for line in f:
        brace = line.find('{')
        if brace == -1: continue
        try:
            p  = json.loads(line[brace:])
            bn = p.get('bar_number')
            cb = p.get('current_bar', {})
            bars[bn] = {'high': cb.get('high'), 'low': cb.get('low')}
        except: continue

sorted_bars = sorted(bars.keys())

# ── 3. Simulate ───────────────────────────────────────────────────────────────
results = []

for t in trades:
    bar_start = t['bar']
    action    = t['action']
    price     = t['price']
    sl        = t['sl']
    sl_pips   = abs(price - sl) * 10000

    pnl    = None
    reason = 'EOW'

    for b in sorted_bars:
        if b <= bar_start: continue
        hi = bars[b]['high']
        lo = bars[b]['low']
        if hi is None or lo is None: continue

        if action == 'OPEN_BUY':
            if (hi - price) * 10000 >= TP_PIPS:
                pnl    = TP_PIPS
                reason = 'TP'
                break
            if lo <= sl:
                pnl    = (sl - price) * 10000   # negative
                reason = 'SL'
                break
        else:
            if (price - lo) * 10000 >= TP_PIPS:
                pnl    = TP_PIPS
                reason = 'TP'
                break
            if hi >= sl:
                pnl    = (price - sl) * 10000   # negative
                reason = 'SL'
                break

    if pnl is None:
        # still open at end of week — count as 0 (flat)
        pnl    = 0
        reason = 'EOW/FLAT'

    results.append({
        'bar':     bar_start,
        'action':  action,
        'price':   price,
        'sl_pips': sl_pips,
        'pnl':     pnl,
        'reason':  reason,
    })

# ── 4. Report ─────────────────────────────────────────────────────────────────
wins   = [r for r in results if r['pnl'] > 0]
losses = [r for r in results if r['pnl'] < 0]
flat   = [r for r in results if r['pnl'] == 0]

gross_win  = sum(r['pnl'] for r in wins)
gross_loss = sum(r['pnl'] for r in losses)
net        = gross_win + gross_loss
pf         = abs(gross_win / gross_loss) if gross_loss else float('inf')

print("=" * 68)
print("LEINTUM — Optimistic P&L  (TP=%d pips, exit at SL or TP)" % TP_PIPS)
print("=" * 68)
print("  %-6s  %-9s  %-8s  %-7s  %-5s  %s" % (
    "Bar","Action","Entry","SL pip","How","P&L (pips)"))
print("  " + "-" * 55)
for r in results:
    sign = "+" if r['pnl'] > 0 else ""
    print("  %-6s  %-9s  %-8.5f  %-7.1f  %-9s  %s%.1f" % (
        r['bar'], r['action'], r['price'], r['sl_pips'],
        r['reason'], sign, r['pnl']))

print()
print("=" * 68)
print("NET P&L SUMMARY  (assuming LLM closes at +%d pips)" % TP_PIPS)
print("=" * 68)
print("  Total trades       : %d" % len(results))
print("  Wins  (hit TP)     : %d   (%.0f%%)" % (len(wins),   100*len(wins)/len(results)   if results else 0))
print("  Losses (hit SL)    : %d   (%.0f%%)" % (len(losses), 100*len(losses)/len(results) if results else 0))
print("  Flat  (EOW, no hit): %d" % len(flat))
print()
print("  Gross profit       : +%.1f pips" % gross_win)
print("  Gross loss         :  %.1f pips" % gross_loss)
print("  NET P&L            : %+.1f pips" % net)
print("  Profit factor      :  %.2f" % pf)
print()
print("  Avg win            : +%.1f pips" % (gross_win/len(wins)    if wins   else 0))
print("  Avg loss           :  %.1f pips" % (gross_loss/len(losses) if losses else 0))
print("  Win/Loss ratio     :  %.2f : 1" % (abs((gross_win/len(wins))/(gross_loss/len(losses))) if wins and losses else 0))
print()
if net > 0:
    print("  VERDICT: PROFITABLE WEEK  (%+.1f pips)" % net)
else:
    print("  VERDICT: LOSING WEEK  (%.1f pips)" % net)
