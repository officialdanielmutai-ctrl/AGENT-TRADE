
require('dotenv').config();

const express = require('express');
const app = express();
app.use(express.json());

const { callLLM } = require('./llm.js');
const { validate } = require('./validator.js');
const { logEntry } = require('./logger.js');
const { buildHold } = require('./fallback.js');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3001;

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
  const start = Date.now();
  const payload = req.body;
  console.log('[heartbeat] received bar:', payload.bar_number ?? '?');
  let decision;
  try {
    const raw = await callLLM(systemPrompt, payload);
    decision = validate(raw);
  } catch (err) {
    console.error('[heartbeat] validation error:', err.message);
    decision = buildHold('VALIDATION_ERROR');
  }
  logEntry({
    ts: new Date().toISOString(),
    type: 'heartbeat',
    bar_number: payload.bar_number ?? 0,
    fallback: decision.fallback ?? false,
    payload,
    response: decision,
    latency_ms: Date.now() - start,
  });
  res.json(decision);
});

app.post('/alert', async (req, res) => {
  const start = Date.now();
  const payload = req.body;
  console.log('[alert] received:', payload.watch_condition ?? '?');
  let decision;
  try {
    const raw = await callLLM(systemPrompt, payload);
    decision = validate(raw);
  } catch (err) {
    console.error('[alert] validation error:', err.message);
    decision = buildHold('VALIDATION_ERROR');
  }
  logEntry({
    ts: new Date().toISOString(),
    type: 'alert',
    bar_number: payload.bar_number ?? 0,
    fallback: decision.fallback ?? false,
    payload,
    response: decision,
    latency_ms: Date.now() - start,
  });
  res.json(decision);
});

// ---------- start ----------
app.listen(PORT, () => {
  console.log(`LEINTUM Bridge stub listening on port ${PORT}`);
});
