import json

log_file = 'logs/session_2026-07-18.jsonl'

decisions = []
benchmark_resp = None
benchmark_payload = None
fallback_count = 0
total = 0

with open(log_file, 'r', encoding='utf-8') as f:
    for line in f:
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except:
            continue

        bar_num = entry.get('bar_number')
        resp = entry.get('response', {})
        total += 1

        if entry.get('fallback'):
            fallback_count += 1
            continue

        action = resp.get('action')

        if bar_num == 35176:
            benchmark_resp = resp
            benchmark_payload = entry.get('payload', {})

        if action in ['OPEN_BUY', 'OPEN_SELL']:
            decisions.append({
                'bar': bar_num,
                'action': action,
                'price': resp.get('entry', {}).get('price'),
                'sl': resp.get('entry', {}).get('sl'),
                'summary': resp.get('reasoning', {}).get('summary', '')[:110]
            })

print("Total bars: %d | Fallbacks: %d | Non-fallback trades: %d" % (total, fallback_count, len(decisions)))
print()
for d in decisions:
    print("Bar %-6s | %-9s | Entry: %s | SL: %s" % (d['bar'], d['action'], d['price'], d['sl']))
    print("  -> %s" % d['summary'])
    print()

print('--- BENCHMARK BAR 35176 ---')
if benchmark_payload:
    pb = benchmark_payload.get('prior_bars', [])
    print("prior_bars injected: %d bars" % len(pb))
    for b in pb:
        print("  bar %s: high=%s body=%s uwk=%s vol=%s" % (
            b.get('bar_number'), b.get('high'), b.get('body_ratio'),
            b.get('upper_wick_ratio'), b.get('volume')))
    cb = benchmark_payload.get('current_bar', {})
    print("  current: high=%s body=%s uwk=%s vol=%s" % (
        cb.get('high'), cb.get('body_ratio'), cb.get('upper_wick_ratio'), cb.get('volume')))
else:
    print("No benchmark payload found.")

if benchmark_resp:
    print("Action: %s" % benchmark_resp.get('action'))
    print("Summary: %s" % benchmark_resp.get('reasoning', {}).get('summary'))
    print('Supporting factors:')
    for sf in benchmark_resp.get('reasoning', {}).get('supporting_factors', []):
        print("  - %s" % sf)
    print('Concerns:')
    for c in benchmark_resp.get('reasoning', {}).get('concerns', []):
        print("  - %s" % c)
    print("Confidence: %s" % benchmark_resp.get('reasoning', {}).get('confidence_reasoning'))
else:
    print('Bar 35176 NOT FOUND in log.')
