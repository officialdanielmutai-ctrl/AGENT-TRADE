const http = require('http');
const fs = require('fs');
const path = require('path');

const PAYLOADS_DIR = path.join(__dirname, 'sample_payloads');
const FILES = [
  'clear_sell.json',
  'clear_buy.json',
  'mixed_hold.json',
  'spike_session.json',
  'open_position_manage.json',
];

const BRIDGE_URL = 'http://localhost:3001/heartbeat';

function postPayload(payload, fileName) {
  return new Promise((resolve) => {
    const start = Date.now();
    const data = JSON.stringify(payload);
    const urlObj = new URL(BRIDGE_URL);
    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port,
      path: urlObj.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      },
    };

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        const latency = Date.now() - start;
        let response;
        try {
          response = JSON.parse(body);
        } catch {
          console.log(`--- [${fileName}] ---`);
          console.log('  (invalid JSON response)');
          console.log(`  Latency: ${latency}ms`);
          console.log('---');
          resolve({ ok: false, fallback: false });
          return;
        }
        const action = response.action ?? '?';
        const decisionType = response.decision_type ?? '?';
        const summary =
          response.reasoning && response.reasoning.summary
            ? response.reasoning.summary
            : '(no summary)';
        const fallback = response.fallback ?? false;

        console.log(`--- [${fileName}] ---`);
        console.log(`  Action:   ${action}`);
        console.log(`  Decision: ${decisionType}`);
        console.log(`  Summary:  ${summary}`);
        console.log(`  Fallback: ${fallback}`);
        console.log(`  Latency:  ${latency}ms`);
        console.log('---');
        resolve({ ok: true, fallback });
      });
    });

    req.on('error', (err) => {
      const latency = Date.now() - start;
      console.log(`--- [${fileName}] ---`);
      console.log(`  Error: ${err.message}`);
      console.log(`  Latency: ${latency}ms`);
      console.log('---');
      resolve({ ok: false, fallback: false });
    });

    req.write(data);
    req.end();
  });
}

async function main() {
  let received = 0;
  let fallbacks = 0;

  for (const file of FILES) {
    const filePath = path.join(PAYLOADS_DIR, file);
    let payload;
    try {
      const raw = fs.readFileSync(filePath, 'utf8');
      payload = JSON.parse(raw);
    } catch (err) {
      console.log(`--- [${file}] ---`);
      console.log(`  Error reading file: ${err.message}`);
      console.log('---');
      continue;
    }

    const result = await postPayload(payload, file);
    if (result.ok) {
      received++;
    }
    if (result.fallback) {
      fallbacks++;
    }
  }

  console.log(`=== DONE: ${received}/5 responses received, ${fallbacks} fallbacks ===`);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
