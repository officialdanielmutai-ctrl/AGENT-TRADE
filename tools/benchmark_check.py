import json
import sys

log_file = 'logs/session_2026-07-17.jsonl'

decisions = []
benchmark_response = None
benchmark_payload = None

try:
    with open(log_file, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip(): continue
            try:
                entry = json.loads(line)
                resp = entry.get('response', {})
                action = resp.get('action')
                bar_num = entry.get('bar_number')
                
                # Check benchmark bar
                if bar_num == 35176:
                    benchmark_response = resp
                    benchmark_payload = entry.get('payload', {})
                
                if action in ['OPEN_BUY', 'OPEN_SELL'] and not resp.get('fallback'):
                    decisions.append({
                        'bar': bar_num,
                        'action': action,
                        'entry': resp.get('entry', {}),
                        'summary': resp.get('reasoning', {}).get('summary', '')[:100]
                    })
            except Exception as e:
                pass
except Exception as e:
    print('Error:', e)

print(f"Total non-fallback trades: {len(decisions)}")
for d in decisions:
    print(f"Bar: {d['bar']:<6} | Action: {d['action']:<10} | Price: {d['entry'].get('price')} | SL: {d['entry'].get('sl')} | Summary: {d['summary']}")

print("\n--- BENCHMARK BAR (35176) ---")
if benchmark_payload:
    print("Payload Current Bar OHLC:")
    print(json.dumps(benchmark_payload.get('current_bar', {}), indent=2))
if benchmark_response:
    print("Action:", benchmark_response.get('action'))
    print("Reasoning:")
    print(json.dumps(benchmark_response.get('reasoning', {}), indent=2))
    entry = benchmark_response.get('entry')
    if entry:
        print(f"Entry Details: TP Basis: {entry.get('tp_basis')}")
else:
    print("Bar 35176 not found in the logs.")
