const { z } = require('zod');

/**
 * Zod schema that validates the LLM response object.
 *
 * Matches the response shape defined in the LEINTUM JSON protocol
 * (Section 8.2 of the blueprint).  Every field is required unless
 * marked `.optional()`.
 */
const decisionSchema = z.object({
  schema_version: z.string(),
  decision_type: z.string(),
  bar_number: z.number(),
  action: z.enum(['OPEN_BUY', 'OPEN_SELL', 'HOLD', 'CLOSE_ALL', 'CLOSE_PARTIAL']),
  entry: z.object({
    price: z.number(),
    sl: z.number(),
    tp: z.number().nullable().optional(),
    tp_basis: z.string().optional(),
    lot_size: z.number(),
  }).nullable(),
  management: z.object({
    action: z.string(),
    sl_adjustment: z.number().nullable().optional(),
    close_percent: z.number().nullable().optional(),
  }).nullable(),
  reasoning: z.object({
    summary: z.string(),
    supporting_factors: z.array(z.string()),
    concerns: z.array(z.string()),
    confidence_reasoning: z.string(),
  }),
  watch: z.array(z.string()),
});

/**
 * Validate an object against the decision schema.
 *
 * @param {unknown} obj - The raw object to validate (typically the
 *   parsed JSON from the LLM response).
 * @returns {object} The validated (and possibly coerced) object.
 * @throws {ZodError} If validation fails — the caller is expected
 *   to catch this and return a fallback HOLD response.
 */
function validate(obj) {
  return decisionSchema.parse(obj);
}

module.exports = { validate };
