import { z } from 'zod';

import {
  generateStructuredJson,
  untrustedTextPart,
  type GeminiPart,
  type SpendGuard,
} from './geminiStructuredCall.js';

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

const payslipInterpretationSchema = z.object({
  employerName: z.string().max(160).nullable(),
  employeeName: z.string().max(160).nullable(),
  payPeriod: z.string().max(80).nullable(),
  paymentDate: z.string().max(40).nullable(),
  currency: z.string().max(8),
  attendance: z.object({
    actualPayableDays: z.number().nonnegative().nullable(),
    totalWorkingDays: z.number().nonnegative().nullable(),
    lossOfPayDays: z.number().nonnegative().nullable(),
    daysPayable: z.number().nonnegative().nullable(),
  }),
  earnings: z.array(z.object({
    label: z.string().max(120),
    canonicalKey: z.string().max(80),
    amount: z.number().finite().min(-100_000_000).max(100_000_000),
    classification: z.enum([
      'basic_pay',
      'hra',
      'allowance',
      'reimbursement',
      'bonus',
      'variable_pay',
      'other',
    ]),
    confidence: z.enum(['high', 'medium', 'low']),
  })).max(80),
  deductions: z.array(z.object({
    label: z.string().max(120),
    canonicalKey: z.string().max(80),
    amount: z.number().finite().min(-100_000_000).max(100_000_000),
    classification: z.enum([
      'income_tax',
      'professional_tax',
      'employee_pf',
      'voluntary_pf',
      'employee_esi',
      'insurance',
      'loan_repayment',
      'housing_recovery',
      'utility_recovery',
      'welfare_contribution',
      'cooperative_recovery',
      'salary_adjustment',
      'other',
    ]),
    confidence: z.enum(['high', 'medium', 'low']),
  })).max(80),
  cumulative: z.array(z.object({
    label: z.string().max(120),
    amount: z.number().finite().min(-100_000_000).max(100_000_000),
    category: z.enum(['earning', 'deduction', 'other']),
    confidence: z.enum(['high', 'medium', 'low']),
  })).max(80).default([]),
  grossEarnings: z.number().nonnegative().nullable(),
  totalDeductions: z.number().nonnegative().nullable(),
  netSalary: z.number().nonnegative().nullable(),
  warnings: z.array(z.string().max(240)).max(20),
  questionsForUser: z.array(z.string().max(240)).max(12),
});

export type PayslipInterpretation = z.infer<typeof payslipInterpretationSchema>;

const payslipResponseSchema = {
  type: 'object',
  properties: {
    employerName: { type: 'string', nullable: true },
    employeeName: { type: 'string', nullable: true },
    payPeriod: { type: 'string', nullable: true },
    paymentDate: { type: 'string', nullable: true },
    currency: { type: 'string' },
    attendance: {
      type: 'object',
      properties: {
        actualPayableDays: { type: 'number', nullable: true },
        totalWorkingDays: { type: 'number', nullable: true },
        lossOfPayDays: { type: 'number', nullable: true },
        daysPayable: { type: 'number', nullable: true },
      },
      required: [
        'actualPayableDays',
        'totalWorkingDays',
        'lossOfPayDays',
        'daysPayable',
      ],
    },
    earnings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string' },
          canonicalKey: { type: 'string' },
          amount: { type: 'number' },
          classification: {
            type: 'string',
            enum: [
              'basic_pay',
              'hra',
              'allowance',
              'reimbursement',
              'bonus',
              'variable_pay',
              'other',
            ],
          },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['label', 'canonicalKey', 'amount', 'classification', 'confidence'],
      },
    },
    deductions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string' },
          canonicalKey: { type: 'string' },
          amount: { type: 'number' },
          classification: {
            type: 'string',
            enum: [
              'income_tax',
              'professional_tax',
              'employee_pf',
              'voluntary_pf',
              'employee_esi',
              'insurance',
              'loan_repayment',
              'housing_recovery',
              'utility_recovery',
              'welfare_contribution',
              'cooperative_recovery',
              'salary_adjustment',
              'other',
            ],
          },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['label', 'canonicalKey', 'amount', 'classification', 'confidence'],
      },
    },
    cumulative: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string' },
          amount: { type: 'number' },
          category: {
            type: 'string',
            enum: ['earning', 'deduction', 'other'],
          },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['label', 'amount', 'category', 'confidence'],
      },
    },
    grossEarnings: { type: 'number', nullable: true },
    totalDeductions: { type: 'number', nullable: true },
    netSalary: { type: 'number', nullable: true },
    warnings: { type: 'array', items: { type: 'string' } },
    questionsForUser: { type: 'array', items: { type: 'string' } },
  },
  required: [
    'employerName',
    'employeeName',
    'payPeriod',
    'paymentDate',
    'currency',
    'attendance',
    'earnings',
    'deductions',
    'cumulative',
    'grossEarnings',
    'totalDeductions',
    'netSalary',
    'warnings',
    'questionsForUser',
  ],
};

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

/// Input tokens assumed for a document sent as bytes rather than as text. A PDF
/// or image is billed per page plus whatever text is extracted from it, none of
/// which can be measured before the upload is sent. So the budget check assumes a
/// document at the expensive end of what the 10MB upload limit allows. Text
/// documents are measured directly and need no such assumption.
const ASSUMED_BYTE_DOCUMENT_INPUT_TOKENS = 60_000;

export type DocumentSource = {
  spendGuard: SpendGuard;
  bytes?: Buffer;
  mimeType?: string;
  documentText?: string;
};

function documentParts(source: DocumentSource): GeminiPart[] {
  if (source.documentText) {
    return [untrustedTextPart(source.documentText)];
  }
  if (source.bytes && source.mimeType) {
    return [{
      inlineData: {
        mimeType: source.mimeType,
        data: source.bytes.toString('base64'),
      },
    }];
  }
  return [];
}

async function interpretDocument(request: {
  label: string;
  systemInstruction: string;
  instruction: string;
  responseSchema: unknown;
  source: DocumentSource;
}): Promise<unknown | null> {
  return generateStructuredJson({
    label: request.label,
    systemInstruction: request.systemInstruction,
    parts: [
      { text: request.instruction },
      ...documentParts(request.source),
    ],
    responseSchema: request.responseSchema,
    assumedInputTokens: request.source.documentText
      ? 0
      : ASSUMED_BYTE_DOCUMENT_INPUT_TOKENS,
    spendGuard: request.source.spendGuard,
  });
}

export async function interpretOfferLetter(
  source: DocumentSource,
): Promise<OfferLetterInterpretation | null> {
  const raw = await interpretDocument({
    label: 'offer-letter',
    systemInstruction: 'Interpret Indian employment offer letters. Extract only values visible in the document. Never calculate tax, invent missing amounts, or resolve ambiguity. Return null for absent amounts and create a user question for every material uncertainty.',
    instruction: 'Extract the compensation promise for user review. Amounts must use the currency units printed in the document.',
    responseSchema,
    source,
  });
  if (raw === null) return null;
  const parsed = offerLetterInterpretationSchema.safeParse(
    normalizeInterpretation(raw),
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
}

export async function interpretPayslip(
  source: DocumentSource,
): Promise<PayslipInterpretation | null> {
  const raw = await interpretDocument({
    label: 'payslip',
    systemInstruction: 'Interpret Indian payslips, including bilingual and non-standard layouts. Read the whole document before classifying any row. Extract only values visible in the document. Keep current-month earnings, current-month deductions or recoveries, employer contributions, and cumulative or year-to-date values separate. Return every printed current-month row, including unfamiliar deductions, under exactly one section. Classifications must be mutually exclusive and collectively exhaustive: choose exactly one allowed classification for every row, using other only when no specific class fits. Preserve printed negative adjustments as negative amounts. Never calculate tax, invent values, or treat annual CTC or cumulative gross as monthly salary. Return null for missing totals and ask a user question for every material uncertainty.',
    instruction: 'Extract pay period, attendance, every current-month earning, every current-month deduction or recovery, every cumulative or year-to-date row, gross earnings, total deductions, and net salary for user review. Use the printed monthly totals even when taxable and non-taxable labels differ. Preserve each source label. Give every earning and deduction a lowercase snake_case canonicalKey that represents its semantic subcategory. Use the same canonicalKey for true aliases such as ITAX and income tax, but keep distinct concepts such as employee PF and voluntary PF separate. Assign exactly one classification to every row. Do not return the same printed row twice even when OCR sources repeat it.',
    responseSchema: payslipResponseSchema,
    source,
  });
  if (raw === null) return null;
  const parsed = payslipInterpretationSchema.safeParse(
    normalizePayslipInterpretation(raw),
  );
  if (!parsed.success) {
    const issues = parsed.error.issues.map((issue) => ({
      path: issue.path.join('.'),
      code: issue.code,
      message: issue.message,
    }));
    console.warn(`[Gemini] invalid payslip output: ${JSON.stringify(issues)}`);
    return null;
  }
  return parsed.data;
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

function canonicalKeyFromLabel(value: unknown): string {
  if (typeof value !== 'string') return 'unknown';
  return value
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80) || 'unknown';
}

function normalizePayslipInterpretation(value: unknown): unknown {
  if (!value || typeof value !== 'object') return value;
  const raw = value as Record<string, unknown>;
  const clamp = (input: unknown, max: number) =>
    typeof input === 'string' ? input.slice(0, max) : input;
  const clampRows = (input: unknown) => Array.isArray(input)
    ? input.slice(0, 80).map((row) => {
      if (!row || typeof row !== 'object') return row;
      const fields = row as Record<string, unknown>;
      return {
        ...fields,
        label: clamp(fields.label, 120),
        canonicalKey: clamp(
          fields.canonicalKey ?? canonicalKeyFromLabel(fields.label),
          80,
        ),
      };
    })
    : input;
  const clampList = (input: unknown, maxItems: number, maxLength: number) =>
    Array.isArray(input)
      ? input.slice(0, maxItems).map((item) => clamp(item, maxLength))
      : input;

  return {
    ...raw,
    employerName: clamp(raw.employerName, 160),
    employeeName: clamp(raw.employeeName, 160),
    payPeriod: clamp(raw.payPeriod, 80),
    paymentDate: clamp(raw.paymentDate, 40),
    currency: clamp(raw.currency, 8),
    earnings: clampRows(raw.earnings),
    deductions: clampRows(raw.deductions),
    cumulative: clampRows(raw.cumulative ?? []),
    warnings: clampList(raw.warnings, 20, 240),
    questionsForUser: clampList(raw.questionsForUser, 12, 240),
  };
}
