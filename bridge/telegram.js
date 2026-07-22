/**
 * telegram.js — Fire-and-forget Telegram notifications for LEINTUM events.
 * Reads TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID from .env.
 * No external dependencies — uses the built-in https module.
 */

const https = require('https');

const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const CHAT_ID   = process.env.TELEGRAM_CHAT_ID;

/**
 * Send a Telegram message. Fire-and-forget — never throws.
 * @param {string} text  Plain text or HTML message
 */
function sendMessage(text) {
  if (!BOT_TOKEN || !CHAT_ID) {
    // Silently skip if not configured — don't crash the Bridge
    return;
  }

  const body = JSON.stringify({
    chat_id:    CHAT_ID,
    text:       text,
    parse_mode: 'HTML',
  });

  const options = {
    hostname: 'api.telegram.org',
    path:     `/bot${BOT_TOKEN}/sendMessage`,
    method:   'POST',
    headers:  { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
  };

  const req = https.request(options, res => {
    // Drain response to free socket
    res.on('data', () => {});
    res.on('end',  () => {});
  });

  req.on('error', err => {
    // Log but never throw — Telegram failure must not affect trading
    console.error('[LEINTUM] Telegram error:', err.message);
  });

  req.write(body);
  req.end();
}

// ── Formatted notification builders ──────────────────────────────────────────

/**
 * Notify on new trade entry.
 */
function notifyTrade(action, price, sl, confidence, summary, barNumber) {
  const emoji = action === 'OPEN_BUY' ? '🟢' : '🔴';
  const dir   = action === 'OPEN_BUY' ? 'BUY' : 'SELL';
  const text  =
    `${emoji} <b>LEINTUM ${dir}  EURUSD</b>\n` +
    `Entry: <code>${price.toFixed(5)}</code>  SL: <code>${sl.toFixed(5)}</code>\n` +
    `Bar: <code>${barNumber}</code>\n` +
    `<i>${summary}</i>`;
  sendMessage(text);
}

/**
 * Notify on emergency close.
 */
function notifyEmergencyClose(healthScore, price) {
  const text =
    `🚨 <b>EMERGENCY CLOSE — EURUSD</b>\n` +
    `Health score: <code>${healthScore.toFixed(1)}</code>\n` +
    `Close price: <code>${price.toFixed(5)}</code>`;
  sendMessage(text);
}

/**
 * Notify when health score drops below caution threshold.
 */
function notifyHealthWarning(healthScore) {
  const text =
    `⚠️ <b>LEINTUM Health Warning</b>\n` +
    `Health score dropped to <code>${healthScore.toFixed(1)}</code> — position under pressure.`;
  sendMessage(text);
}

/**
 * Notify when daily loss limit is hit.
 */
function notifyDailyLimit(lossAmount) {
  const text =
    `🛑 <b>LEINTUM Daily Loss Limit Hit</b>\n` +
    `Total loss today: <code>${lossAmount.toFixed(2)}</code>. No further entries today.`;
  sendMessage(text);
}

/**
 * Notify on Bridge restart / reconnect.
 */
function notifyBridgeRestart(timestamp) {
  const text =
    `🔄 <b>LEINTUM Bridge Restarted</b>\n` +
    `Time: <code>${timestamp}</code>`;
  sendMessage(text);
}

/**
 * Notify on intra-bar event from EventTriggerMonitor.
 */
function notifyEvent(eventType, detail, price) {
  const text =
    `📡 <b>LEINTUM Event: ${eventType}</b>\n` +
    `${detail}\n` +
    `Price: <code>${price}</code>`;
  sendMessage(text);
}

module.exports = {
  sendMessage,
  notifyTrade,
  notifyEmergencyClose,
  notifyHealthWarning,
  notifyDailyLimit,
  notifyBridgeRestart,
  notifyEvent,
};
