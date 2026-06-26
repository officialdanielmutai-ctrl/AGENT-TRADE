
require('dotenv').config();

const express = require('express');
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3001;

// ---------- stub response shape ----------
function stubResponse(decisionType) {
  return {
    schema_version: '1.0',
    decision_type: decisionType,
    bar_number: 0,
    action: 'HOLD',
    entry: null,
    management: null,
    reasoning: {
      summary: 'Stub response — LLM not yet wired in (Unit 01).',
      supporting_factors: [],
      concerns: [],
      confidence_reasoning: '',
    },
    watch: [],
  };
}

// ---------- routes ----------
app.get('/status', (_req, res) => {
  res.json({ ok: true });
});

app.post('/heartbeat', (req, res) => {
  console.log('[heartbeat] received:', JSON.stringify(req.body));
  res.json(stubResponse('HEARTBEAT_RESPONSE'));
});

app.post('/alert', (req, res) => {
  console.log('[alert] received:', JSON.stringify(req.body));
  res.json(stubResponse('ALERT_RESPONSE'));
});

// ---------- start ----------
app.listen(PORT, () => {
  console.log(`LEINTUM Bridge stub listening on port ${PORT}`);
});
