const fallback = require('./fallback.js');

/**
 * Calls the DeepSeek API (OpenAI‑compatible) with the given system prompt
 * and payload.  Wraps the call in a Promise.race() against a configurable
 * timeout.  Returns the parsed JSON decision object on success, or a
 * fallback HOLD response on any failure (timeout, invalid JSON, network
 * error, etc.).
 *
 * @param {string} systemPrompt - The full LEINTUM system prompt text.
 * @param {object} payload      - The market state payload from the EA.
 * @returns {Promise<object>}   - The validated decision object.
 */
async function callLLM(systemPrompt, payload) {
  const timeoutMs = Number(process.env.LLM_TIMEOUT_MS) || 8000;

  try {
    const response = await Promise.race([
      fetch('https://api.deepseek.com/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: 'Bearer ' + process.env.ANTHROPIC_API_KEY,
        },
        body: JSON.stringify({
          model: process.env.LLM_MODEL,
          max_tokens: 1000,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: JSON.stringify(payload) },
          ],
        }),
      }),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('TIMEOUT')), timeoutMs)
      ),
    ]);

    const data = await response.json();

    // Guard: if DeepSeek returns an error body (e.g. invalid key, quota
    // exceeded, unknown model) it has no choices array.  Log the full
    // response so the operator can see the exact API error, then fall back.
    if (!data.choices || data.choices.length === 0) {
      console.error('[llm] API returned no choices — full response:', JSON.stringify(data));
      return fallback.buildHold('LLM_ERROR');
    }

    const text = data.choices[0].message.content;
    const parsed = JSON.parse(text);
    return parsed;
  } catch (err) {
    if (err.message === 'TIMEOUT') {
      console.error('[llm] timeout — returning fallback');
      return fallback.buildHold('LLM_TIMEOUT');
    }

    if (err instanceof SyntaxError) {
      console.error('[llm] invalid JSON — returning fallback');
      return fallback.buildHold('INVALID_JSON');
    }

    console.error('[llm] error:', err.message);
    return fallback.buildHold('LLM_ERROR');
  }
}

module.exports = { callLLM };
