const Anthropic = require('@anthropic-ai/sdk');
const fallback = require('./fallback.js');

/**
 * Calls the Anthropic Claude API with the given system prompt and payload.
 * Wraps the call in a Promise.race() against a configurable timeout.
 * Returns the parsed JSON decision object on success, or a fallback HOLD
 * response on any failure (timeout, invalid JSON, network error, etc.).
 *
 * @param {string} systemPrompt - The full LEINTUM system prompt text.
 * @param {object} payload      - The market state payload from the EA.
 * @returns {Promise<object>}   - The validated decision object.
 */
async function callLLM(systemPrompt, payload) {
  const client = new Anthropic({
    apiKey: process.env.ANTHROPIC_API_KEY,
  });

  const timeoutMs = Number(process.env.LLM_TIMEOUT_MS) || 8000;

  try {
    const response = await Promise.race([
      client.messages.create({
        model: process.env.LLM_MODEL,
        max_tokens: 1000,
        system: systemPrompt,
        messages: [
          { role: 'user', content: JSON.stringify(payload) },
        ],
      }),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('TIMEOUT')), timeoutMs)
      ),
    ]);

    const text = response.content[0].text;
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
