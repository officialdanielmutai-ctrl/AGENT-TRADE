/**
 * Build a fallback HOLD response when the LLM is unreachable or
 * returns an invalid response.
 *
 * @param {string} reason - Human-readable explanation of why the
 *   fallback was triggered.
 * @returns {object} A fully-formed fallback response object matching
 *   the Zod schema expected by the EA.
 */
function buildHold(reason) {
  return {
    schema_version: '1.0',
    decision_type: 'FALLBACK',
    bar_number: 0,
    action: 'HOLD',
    entry: null,
    management: null,
    fallback: true,
    fallback_reason: reason,
    reasoning: {
      summary: 'Fallback HOLD — LLM unreachable or response invalid.',
      supporting_factors: [],
      concerns: [],
      confidence_reasoning: '',
    },
    watch: [],
  };
}

module.exports = { buildHold };
