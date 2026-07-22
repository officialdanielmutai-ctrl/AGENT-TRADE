
require('dotenv').config();

const express = require('express');
const http    = require('http');
const { WebSocketServer } = require('ws');
const app    = express();
const server = http.createServer(app);
const wss    = new WebSocketServer({ server });
app.use(express.json());
app.use((_req, res, next) => { res.header('Access-Control-Allow-Origin', '*'); next(); });

const { callLLM }   = require('./llm.js');
const { validate }  = require('./validator.js');
const { logEntry }  = require('./logger.js');
const { buildHold } = require('./fallback.js');
const telegram      = require('./telegram.js');
const fs   = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3001;

// ---------- WebSocket broadcast helper ----------
function broadcast(data) {
  const msg = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState === 1) client.send(msg);
  });
}

// ---------- load system prompt once at startup ----------
const SYSTEM_PROMPT_PATH = path.join(__dirname, 'system_prompt.txt');
let systemPrompt = '';
try {
  systemPrompt = fs.readFileSync(SYSTEM_PROMPT_PATH, 'utf8');
} catch (_) {
  console.warn('[server] system_prompt.txt not found — LLM calls will use empty prompt until it is created');
}

// ---------- routes ----------
app.get('/status', (_req, res) => {
  res.json({ ok: true });
});

app.post('/heartbeat', async (req, res) => {
  const start   = Date.now();
  const payload = req.body;
  console.log('[heartbeat] received bar:', payload.bar_number ?? '?');
  let decision;
  try {
    const raw = await callLLM(systemPrompt, payload);
    decision  = validate(raw);
  } catch (err) {
    console.error('[heartbeat] validation error:', err.message);
    decision = buildHold('VALIDATION_ERROR');
  }

  const logRow = {
    ts:         new Date().toISOString(),
    type:       'heartbeat',
    bar_number: payload.bar_number ?? 0,
    fallback:   decision.fallback ?? false,
    payload,
    response:   decision,
    latency_ms: Date.now() - start,
  };
  logEntry(logRow);
  broadcast({ type: 'heartbeat', ...logRow });

  // Telegram — notify on trade entry
  if (!decision.fallback && ['OPEN_BUY','OPEN_SELL'].includes(decision.action)) {
    const ent = decision.entry || {};
    telegram.notifyTrade(
      decision.action,
      ent.price  || 0,
      ent.sl     || 0,
      0,
      decision.reasoning?.summary || '',
      payload.bar_number ?? 0
    );
  }

  res.json(decision);
});

app.post('/alert', async (req, res) => {
  const start   = Date.now();
  const payload = req.body;
  console.log('[alert] received:', payload.event ?? '?');
  let decision;
  try {
    const raw = await callLLM(systemPrompt, payload);
    decision  = validate(raw);
  } catch (err) {
    console.error('[alert] validation error:', err.message);
    decision = buildHold('VALIDATION_ERROR');
  }

  const logRow = {
    ts:         new Date().toISOString(),
    type:       'alert',
    bar_number: payload.bar_number ?? 0,
    fallback:   decision.fallback ?? false,
    payload,
    response:   decision,
    latency_ms: Date.now() - start,
  };
  logEntry(logRow);
  broadcast({ type: 'alert', ...logRow });

  // Telegram — notify on significant events
  if (payload.event) {
    telegram.notifyEvent(payload.event, payload.detail || '', payload.price || 0);
  }

  res.json(decision);
});

// ---------- start ----------
server.listen(PORT, () => {
  console.log(`LEINTUM Bridge listening on port ${PORT}`);
  telegram.notifyBridgeRestart(new Date().toISOString());
});
