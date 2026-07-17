import json
import sys

# Load log file
log_file = 'logs/session_2026-07-16.jsonl'
decisions = []
try:
    with open(log_file, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip(): continue
            try:
                entry = json.loads(line)
                resp = entry.get('response', {})
                action = resp.get('action')
                if action in ['OPEN_BUY', 'OPEN_SELL'] and not resp.get('fallback'):
                    decisions.append({
                        'bar': entry.get('bar_number'),
                        'action': action,
                        'entry': resp.get('entry', {})
                    })
            except Exception: pass
except Exception as e:
    print('Error:', e)

# Find timestamps from payload_june.txt
bar_to_time = {}
try:
    with open('payload_june.txt', 'r', encoding='utf-8') as f:
        for line in f:
            if '[LEINTUM]' in line and 'Payload:' in line:
                parts = line.split('[LEINTUM]')
                prefix = parts[0]
                brace_pos = line.find('{')
                if brace_pos == -1: continue
                json_part = line[brace_pos:]
                try:
                    payload = json.loads(json_part)
                    bar_num = payload.get('bar_number')
                    # extract timestamp from prefix (e.g. '2026.06.02 16:00:00')
                    ts = prefix.split(')')[1].strip() if ')' in prefix else 'Unknown'
                    bar_to_time[bar_num] = ts
                except: pass
except: pass

print('Executed Trades:')
for d in decisions:
    print(f"Bar: {d['bar']:<6} | Time: {bar_to_time.get(d['bar'], 'Unknown'):<20} | Action: {d['action']:<10} | LLM Entry: {d['entry']}")
