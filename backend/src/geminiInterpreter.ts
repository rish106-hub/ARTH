import { z } from 'zod';

const offerLetterInterpretationSchema = z.object({
  employerName: z.string().max(160).nullable(),
  roleTitle: z.string().max(160).nullable(),
  currency: z.string().max(8),
  annualCtc: z.number().nonnegative().nullable(),
  fixedAnnualPay: z.number().nonnegative().nullable(),
  variableAnnualPay: z.number().nonnegative().nullable(),
  joiningBonus: z.number().nonnegative().nullable(),
  components: z.array(z.object({
    label: z.string().max(120),
    annualAmount: z.number().nonnegative().nullable(),
    frequency: z.enum(['monthly', 'quarterly', 'annual', 'one_time', 'unknown']),
    classification: z.enum([
      'fixed_pay',
      'variable_pay',
      'allowance',
      'reimbursement',
      'employer_contribution',
      'deduction',
      'other',
    ]),
    confidence: z.enum(['high', 'medium', 'low']),
  })).max(80),
  warnings: z.array(z.string().max(240)).max(20),
  questionsForUser: z.array(z.string().max(240)).max(12),
});

export type OfferLetterInterpretation = z.infer<typeof offerLetterInterpretationSchema>;

const responseSchema = {
  type: 'object',
  properties: {
    employerName: { type: 'string', nullable: true, description: 'At most 160 characters.' },
    roleTitle: { type: 'string', nullable: true, description: 'At most 160 characters.' },
    currency: { type: 'string', description: 'Currency code or symbol, at most 8 characters.' },
    annualCtc: { type: 'number', nullable: true },
    fixedAnnualPay: { type: 'number', nullable: true },
    variableAnnualPay: { type: 'number', nullable: true },
    joiningBonus: { type: 'number', nullable: true },
    components: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string', description: 'At most 120 characters.' },
          annualAmount: { type: 'number', nullable: true },
          frequency: {
            type: 'string',
            enum: ['monthly', 'quarterly', 'annual', 'one_time', 'unknown'],
          },
          classification: {
            type: 'string',
            enum: [
              'fixed_pay',
              'variable_pay',
              'allowance',
              'reimbursement',
              'employer_contribution',
              'deduction',
              'other',
            ],
          },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['label', 'annualAmount', 'frequency', 'classification', 'confidence'],
      },
    },
    warnings: {
      type: 'array',
      items: { type: 'string', description: 'At most 240 characters.' },
    },
    questionsForUser: {
      type: 'array',
      items: { type: 'string', description: 'At most 240 characters.' },
    },
  },
  required: [
    'employerName',
    'roleTitle',
    'currency',
    'annualCtc',
    'fixedAnnualPay',
    'variableAnnualPay',
    'joiningBonus',
    'components',
    'warnings',
    'questionsForUser',
  ],
};

export async function interpretOfferLetter(input: {
  bytes: Buffer;
  mimeType: string;
}): Promise<OfferLetterInterpretation | null> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return null;
  const model = process.env.GEMINI_MODEL || 'gemini-3.6-flash';
  const configuredTimeout = Number.parseInt(
    process.env.GEMINI_TIMEOUT_MS || '25000',
    10,
  );
  const timeoutMs = Number.isFinite(configuredTimeout)
    ? Math.min(Math.max(configuredTimeout, 1_000), 60_000)
    : 25_000;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
    const response = await fetch(endpoint, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify({
        store: false,
        systemInstruction: {
          parts: [{
            text: 'Interpret Indian employment offer letters. Extract only values visible in the document. Never calculate tax, invent missing amounts, or resolve ambiguity. Return null for absent amounts and create a user question for every material uncertainty.',
          }],
        },
        contents: [{
          role: 'user',
          parts: [
            { text: 'Extract the compensation promise for user review. Amounts must use the currency units printed in the document.' },
            {
              inlineData: {
                mimeType: input.mimeType,
                data: input.bytes.toString('base64'),
              },
            },
          ],
        }],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema,
        },
      }),
    });
    if (!response.ok) {
      const errorBody = await response.text();
      console.warn(
        `[Gemini] offer-letter interpretation failed (${response.status}): ${errorBody.slice(0, 500)}`,
      );
      return null;
    }
    const payload = await response.json() as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const text = payload.candidates?.[0]?.content?.parts
      ?.map((part) => part.text ?? '')
      .join('')
      .trim();
    if (!text) return null;
    const parsed = offerLetterInterpretationSchema.safeParse(
      normalizeInterpretation(JSON.parse(text)),
    );
    if (!parsed.success) {
      const issues = parsed.error.issues.map((issue) => ({
        path: issue.path.join('.'),
        code: issue.code,
        message: issue.message,
      }));
      console.warn(`[Gemini] invalid offer-letter output: ${JSON.stringify(issues)}`);
      return null;
    }
    return parsed.data;
  } catch (error) {
    const reason = error instanceof Error ? error.name : 'unknown_error';
    console.warn(`[Gemini] offer-letter interpretation failed: ${reason}`);
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeInterpretation(value: unknown): unknown {
  if (!value || typeof value !== 'object') return value;
  const raw = value as Record<string, unknown>;
  const clamp = (input: unknown, max: number) =>
    typeof input === 'string' ? input.slice(0, max) : input;
  const clampList = (input: unknown, maxItems: number, maxLength: number) =>
    Array.isArray(input)
      ? input.slice(0, maxItems).map((item) => clamp(item, maxLength))
      : input;
  const components = Array.isArray(raw.components)
    ? raw.components.slice(0, 80).map((component) => {
      if (!component || typeof component !== 'object') return component;
      const fields = component as Record<string, unknown>;
      return { ...fields, label: clamp(fields.label, 120) };
    })
    : raw.components;

  return {
    ...raw,
    employerName: clamp(raw.employerName, 160),
    roleTitle: clamp(raw.roleTitle, 160),
    currency: clamp(raw.currency, 8),
    components,
    warnings: clampList(raw.warnings, 20, 240),
    questionsForUser: clampList(raw.questionsForUser, 12, 240),
  };
}
