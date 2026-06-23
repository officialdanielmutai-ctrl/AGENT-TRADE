# UI Context

LEINTUM has two monitoring surfaces. Both are internal operator tools —
not public-facing product UIs. Keep them functional and readable, not
polished. No framework, no build step, no dependencies beyond vanilla
JS and the WebSocket API.

## 1. Session Log Viewer (`dashboard/viewer.html`)

A standalone HTML file that reads the daily JSONL log and renders
every decision in a scrollable, colour-coded list. The operator uses
this for end-of-day review — it must load in a browser by
double-clicking the file (no server required for the viewer itself).

### Layout

```
┌─────────────────────────────────────────────────┐
│  LEINTUM Session Log  [date picker]  [load btn] │
├─────────────────────────────────────────────────┤
│  Summary bar: X calls · Y trades · Z pips net  │
├─────────────────────────────────────────────────┤
│  [SELL ▼] 09:15  bar 847  conviction 0.82       │
│  Regime: TRENDING_DOWN · Momentum: WAXING       │
│  Reasoning: …summary text…                      │
│  ▶ expand full reasoning + payload              │
├─────────────────────────────────────────────────┤
│  [HOLD]   09:30  bar 848  —                     │
│  Session: SPIKE · blocked at step 1             │
│  ▶ expand                                       │
└─────────────────────────────────────────────────┘
```

### Colour coding

| Action | Row accent colour |
|---|---|
| OPEN_BUY | Green left border (`#22c55e`) |
| OPEN_SELL | Red left border (`#ef4444`) |
| HOLD | Grey left border (`#6b7280`) |
| CLOSE_ALL / CLOSE_PARTIAL | Amber left border (`#f59e0b`) |
| Fallback HOLD (LLM unreachable) | Orange left border (`#f97316`) |

### Behaviour

- Default view: collapsed cards, one per log entry, newest at top.
- Expand toggle: shows full `reasoning` block (summary, supporting
  factors, concerns, confidence reasoning) and the raw payload JSON
  in a `<pre>` block.
- Summary bar recomputes on load: count total calls, count OPEN
  actions, compute net pips from closed positions in the log.
- Date picker defaults to today. On change, re-reads the matching
  `logs/session_YYYY-MM-DD.jsonl` file via `fetch()` (works when
  served from a local HTTP server; note `file://` fetch is blocked by
  CORS in most browsers — operator should run `npx serve .` or use
  VS Code Live Server).
- No charts, no canvas. Text and colour only — loads instantly.

## 2. Live Dashboard (`dashboard/live.html`)

A single-page HTML file that connects to the WebSocket server
(`ws_server.js`) and displays the current system state in real time.
Refreshes on every WebSocket message — no polling.

### Layout

```
┌──────────────────────────────────────────────────────┐
│  LEINTUM LIVE          ● CONNECTED   09:27:43 GMT   │
├────────────┬─────────────┬────────────┬──────────────┤
│  SESSION   │  REGIME     │  MOMENTUM  │  CONVICTION  │
│  HOT       │  TRENDING↓  │  WAXING    │  0.82        │
├────────────┴─────────────┴────────────┴──────────────┤
│  OPEN POSITIONS                                      │
│  #1042  SELL  entry 1.08520  PnL +4.2p  Health 74  │
├──────────────────────────────────────────────────────┤
│  LAST DECISION  [09:15]  OPEN_SELL                  │
│  "HTF aligned bearish. Distribution ceiling at      │
│   1.08522 confirmed by volume drop. Entering sell." │
├──────────────────────────────────────────────────────┤
│  CROSS-PAIR ENERGY                                   │
│  GBP ACTIVE ↓  CHF ACTIVE ↑  JPY COASTING          │
│  AUD DEAD      XAU ACTIVE ↓  OIL COASTING          │
└──────────────────────────────────────────────────────┘
```

### Behaviour

- WebSocket connects to `ws://localhost:3002` on page load.
- On disconnect: show red `● DISCONNECTED` indicator. Retry every
  5 seconds.
- Every incoming message is a JSON object with shape:
  `{ type: "heartbeat"|"alert"|"status", payload: {...} }`
- `heartbeat`: update all panels with latest state.
- `alert`: flash the relevant position row amber for 3 seconds.
- `status`: update the connection indicator only.
- Health score colour: ≥ 60 green, 25–59 amber, < 25 red.
- No history — the live dashboard shows current state only. History
  is the viewer's job.

## 3. General Visual Conventions

- Font: system monospace (`font-family: monospace`) for all numeric
  values and JSON. System sans-serif for labels and prose.
- Background: dark (`#0f172a`). Text: `#e2e8f0`. Muted: `#64748b`.
- No external CSS frameworks. Inline `<style>` block only.
- No images, icons, or SVG decorations — text labels only.
- Both files must render correctly at 1280px wide minimum. No
  mobile-responsive requirement (operator tool, desktop only).
