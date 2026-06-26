const fs = require('fs');
const path = require('path');

/**
 * Append a single JSON line to the session log file.
 *
 * The log file path is built from:
 *   process.env.LOG_PATH || '../logs'
 * plus the current date in YYYY-MM-DD format.
 *
 * Errors are silently swallowed so that a logging failure never
 * crashes the Bridge or delays the response to the EA.
 *
 * @param {object} entry - The object to serialise and append.
 * @returns {void}
 */
function logEntry(entry) {
  try {
    const logDir = process.env.LOG_PATH || '../logs';
    const dateStr = new Date().toISOString().slice(0, 10);
    const filePath = path.join(logDir, `session_${dateStr}.jsonl`);

    const line = JSON.stringify(entry) + '\n';
    fs.appendFile(filePath, line, (err) => {
      // Swallow any error silently — logging must never throw.
      if (err) {
        // noop
      }
    });
  } catch (_err) {
    // Swallow all synchronous errors as well.
  }
}

module.exports = { logEntry };
