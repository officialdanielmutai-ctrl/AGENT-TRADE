import json
import sys

# 1. Load the trades
trades = []
with open('logs/session_2026-07-17.jsonl', 'r', encoding='utf-8') as f:
    for line in f:
        if not line.strip(): continue
        try:
            entry = json.loads(line)
            resp = entry.get('response', {})
            action = resp.get('action')
            if action in ['OPEN_BUY', 'OPEN_SELL'] and not resp.get('fallback'):
                trades.append({
                    'bar': entry.get('bar_number'),
                    'action': action,
                    'price': resp.get('entry', {}).get('price'),
                    'sl': resp.get('entry', {}).get('sl'),
                    'tp': resp.get('entry', {}).get('tp')
                })
        except: pass

# 2. Load the price action data from the payloads
bars = {}
with open('payload_june.txt', 'r', encoding='utf-8') as f:
    for line in f:
        if '[LEINTUM]' not in line or 'Payload:' not in line: continue
        brace_pos = line.find('{')
        if brace_pos == -1: continue
        try:
            payload = json.loads(line[brace_pos:])
            bar_num = payload.get('bar_number')
            curr = payload.get('current_bar', {})
            bars[bar_num] = {
                'high': curr.get('high'),
                'low': curr.get('low'),
                'close': curr.get('close')
            }
        except: pass

# 3. Simulate the outcome
print("Trade Simulation Results (June 1 - June 5, 2026)\n" + "-"*70)

total_trades = len(trades)
wins = 0
losses = 0
open_trades = 0

for t in trades:
    bar_start = t['bar']
    action = t['action']
    entry_price = t['price']
    sl = t['sl']
    tp = t['tp']
    
    if not entry_price or not sl:
        print(f"Bar {bar_start:<5} | {action:<9} | Invalid Entry/SL. Skipping.")
        continue

    outcome = "OPEN (EOW)"
    mfe = 0.0 # Max Favorable Excursion (pips)
    mae = 0.0 # Max Adverse Excursion (pips)
    exit_price = None

    # Scan forward
    for b in sorted(bars.keys()):
        if b <= bar_start: continue
        
        high = bars[b]['high']
        low = bars[b]['low']
        if high is None or low is None: continue

        if action == 'OPEN_BUY':
            # Check for MFE/MAE
            mfe = max(mfe, (high - entry_price) * 10000)
            mae = min(mae, (low - entry_price) * 10000)

            # Check SL
            if low <= sl:
                outcome = "LOSS (Hit SL)"
                exit_price = sl
                break
            
            # Check TP
            if tp and high >= tp:
                outcome = "WIN (Hit TP)"
                exit_price = tp
                break

        elif action == 'OPEN_SELL':
            # Check for MFE/MAE
            mfe = max(mfe, (entry_price - low) * 10000)
            mae = min(mae, (entry_price - high) * 10000)

            # Check SL
            if high >= sl:
                outcome = "LOSS (Hit SL)"
                exit_price = sl
                break
            
            # Check TP
            if tp and low <= tp:
                outcome = "WIN (Hit TP)"
                exit_price = tp
                break

    if "LOSS" in outcome: losses += 1
    elif "WIN" in outcome: wins += 1
    else: open_trades += 1
    
    tp_str = f"{tp:.5f}" if tp else "MANAGED"
    
    print(f"Bar {bar_start:<5} | {action:<9} | Entry: {entry_price:.5f} | SL: {sl:.5f} | TP: {tp_str}")
    print(f"  -> Outcome: {outcome:<13} | MFE: +{mfe:.1f} pips | MAE: {mae:.1f} pips")
    print("-" * 70)

print(f"\nSummary: {wins} Wins, {losses} Losses, {open_trades} Still Open at End of Week.")
