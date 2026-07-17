import json
from collections import Counter
import sys

log_file = 'logs/session_2026-07-16.jsonl'
actions = Counter()
decisions = []

try:
    with open(log_file, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip(): continue
            try:
                entry = json.loads(line)
                response = entry.get('response', {})
                action = response.get('action', 'UNKNOWN')
                actions[action] += 1
                if action != 'HOLD' or response.get('fallback') == False:
                    # Let's collect all non-fallback decisions to see what Claude did
                    if response.get('fallback') == True:
                        continue
                        
                    decisions.append({
                        'bar': entry.get('bar_number'),
                        'action': action,
                        'reasoning': response.get('reasoning', {}).get('summary', '')[:200]
                    })
            except Exception as e:
                pass
except Exception as e:
    print('Error reading log:', e)

print('Total actions:', dict(actions))
print('\nSample of decisions (first 10 non-fallback):')
for d in decisions[:10]:
    print(f"Bar {d['bar']:<6} | {d['action']:<12} | {d['reasoning']}")
print(f"\nTotal non-fallback decisions: {len(decisions)}")
