"""
backtest_replay.py — Phase 3.3 / 3.4 replay tool for LEINTUM.

Feeds historical payloads through the live Bridge without going through
MT5's Strategy Tester. MT5's WebRequest is sandboxed inside Tester
agents, so this tool is the workaround for the Phase 3.3 benchmark replay.

Input file format — two variants are both accepted:
  1. Raw JSON per line (one JSON object, nothing else)
  2. MT5 Expert log lines — any amount of log prefix before the first
     '{' character is stripped automatically. Example:
       CS  0  18:11:42.676  LEINTUM_Engine (EURUSD,M15)  2026.06.04 23:00:00   [LEINTUM] Payload: {"schema_version":...
     The parser finds the first '{' and slices from there.

Blank lines and lines with no '{' are silently skipped.

Usage:
    python tools/backtest_replay.py payload_june.txt
    python tools/backtest_replay.py payload_june.txt --url http://127.0.0.1:3001/heartbeat
    python tools/backtest_replay.py payload_june.txt --delay 1.0

Standard library only — no external dependencies.
"""

import argparse
import json
import sys
import time
import urllib.request
import urllib.error


# ---------------------------------------------------------------------------
# CLI arguments
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="Replay historical payloads through the LEINTUM Bridge (Phase 3.3)."
    )
    parser.add_argument(
        "payloads_file",
        help="Path to a .txt file containing one JSON payload per line."
    )
    parser.add_argument(
        "--url",
        default="http://127.0.0.1:3001/heartbeat",
        help="Bridge endpoint URL (default: http://127.0.0.1:3001/heartbeat)."
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.5,
        help="Seconds to sleep between requests (default: 0.5)."
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# HTTP POST — returns parsed response dict or raises on failure
# ---------------------------------------------------------------------------

def post_payload(url, payload_dict, timeout_s=30):
    """
    POST payload_dict as JSON to url.

    Returns the parsed JSON response dict on HTTP 2xx.
    Raises urllib.error.URLError on connection errors,
    urllib.error.HTTPError on non-2xx, or ValueError on bad response JSON.
    """
    body = json.dumps(payload_dict).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read().decode("utf-8")
    return json.loads(raw)


# ---------------------------------------------------------------------------
# Format one result line
# ---------------------------------------------------------------------------

def format_result_line(bar_number, response):
    """
    Return a single printable line summarising the Bridge response.

    bar {bar_number} | action={action} | conviction={conviction} | {reasoning_summary}
    """
    action = response.get("action", "?")
    conviction = response.get("conviction", "?")

    # reasoning.summary — nested field, may be absent
    reasoning = response.get("reasoning")
    if isinstance(reasoning, dict):
        summary_raw = reasoning.get("summary", "(no reasoning field)")
    else:
        summary_raw = "(no reasoning field)"

    # Truncate summary to 100 chars
    summary = summary_raw[:100] if len(summary_raw) > 100 else summary_raw

    return f"bar {bar_number} | action={action} | conviction={conviction} | {summary}"


# ---------------------------------------------------------------------------
# Main replay loop
# ---------------------------------------------------------------------------

def main():
    args = parse_args()

    # Read the payloads file
    try:
        with open(args.payloads_file, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError as e:
        print(f"ERROR: Cannot open payloads file: {e}", file=sys.stderr)
        sys.exit(1)

    processed = 0
    errors = 0
    skipped = 0

    # Rolling window of the last N bars so the LLM has structural context.
    # Each entry is a slim summary dict (bar_number + current_bar anatomy).
    HISTORY_WINDOW = 5
    bar_history = []  # most-recent last
    
    # Cooldown tracker to prevent over-triggering
    # Set to 12 bars (3 hours on M15) after an OPEN_BUY or OPEN_SELL
    COOLDOWN_PERIOD = 12
    last_trade_bar = -9999
    last_trade_action = None

    for line_index, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()

        # Skip blank lines silently
        if not line:
            continue

        # --- Phase 1: extract JSON from the line ---
        # The input may be a raw MT5 Expert log line with a variable-length
        # prefix (timestamp, EA name, bar datetime, [LEINTUM] tag) before
        # the JSON object. Find the first '{' and slice from there so both
        # raw-JSON lines and full MT5 log lines are handled identically.
        brace_pos = line.find('{')
        if brace_pos == -1:
            # No JSON object on this line at all — skip silently
            continue
        json_str = line[brace_pos:]

        try:
            payload = json.loads(json_str)
        except json.JSONDecodeError:
            preview = line[:80]
            print(f"SKIP (invalid JSON) line {line_index}: {preview}")
            skipped += 1
            continue

        # bar_number from payload or fall back to line index
        bar_number = payload.get("bar_number", line_index)

        # --- Enrich payload with rolling bar history ---
        # Inject prior_bars so the LLM can spot multi-bar structural patterns
        # (e.g. Distribution Top = 3-4 consecutive rejected tests of a ceiling).
        if bar_history:
            payload["prior_bars"] = bar_history[-HISTORY_WINDOW:]

        # --- Inject Cooldown context ---
        bars_since = bar_number - last_trade_bar
        is_active = (bars_since <= COOLDOWN_PERIOD)
        payload["cooldown"] = {
            "active": is_active,
            "bars_since_last_trade": bars_since if last_trade_bar > 0 else 999,
            "last_action": last_trade_action
        }

        # After we have enriched the payload, snapshot this bar's anatomy
        # for the NEXT iteration's prior_bars.
        current_bar = payload.get("current_bar", {})
        bar_snapshot = {
            "bar_number": bar_number,
            "open":  current_bar.get("open"),
            "high":  current_bar.get("high"),
            "low":   current_bar.get("low"),
            "close": current_bar.get("close"),
            "body_ratio":        current_bar.get("body_ratio"),
            "upper_wick_ratio":  current_bar.get("upper_wick_ratio"),
            "lower_wick_ratio":  current_bar.get("lower_wick_ratio"),
            "volume":     current_bar.get("volume"),
            "volume_avg": current_bar.get("volume_avg"),
        }
        bar_history.append(bar_snapshot)
        if len(bar_history) > HISTORY_WINDOW + 1:
            bar_history.pop(0)

        # --- Phase 2: POST to Bridge and print result ---
        try:
            response = post_payload(args.url, payload)
            print(format_result_line(bar_number, response))
            processed += 1
            
            # Update cooldown if a trade was opened
            action = response.get("action", "")
            if action in ["OPEN_BUY", "OPEN_SELL"]:
                last_trade_bar = bar_number
                last_trade_action = action

        except urllib.error.HTTPError as e:
            print(f"bar {bar_number} | ERROR: HTTP {e.code} {e.reason}")
            errors += 1

        except urllib.error.URLError as e:
            # Covers connection refused, timeout, DNS failure, etc.
            print(f"bar {bar_number} | ERROR: {e.reason}")
            errors += 1

        except json.JSONDecodeError as e:
            print(f"bar {bar_number} | ERROR: Bridge returned invalid JSON — {e}")
            errors += 1

        except Exception as e:  # noqa: BLE001 — catch-all so one bad bar never kills the run
            print(f"bar {bar_number} | ERROR: {e}")
            errors += 1

        # Delay between requests to avoid hammering the Bridge/LLM API
        if args.delay > 0:
            time.sleep(args.delay)

    # --- Summary ---
    print(
        f"Replay complete: {processed} bars processed, "
        f"{errors} errors, {skipped} skipped"
    )


if __name__ == "__main__":
    main()
