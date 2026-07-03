import { PasswordException, PDFParse } from 'pdf-parse';

export type PanVaultSuffix = {
  last4: string;
  lastChar: string;
} | null;

export type DocumentParseResult = {
  status: 'metadata_ready' | 'needs_confirmation' | 'unsupported';
  summary: Record<string, unknown>;
};

type ParsedForm16Fields = {
  employerName?: string;
  employerTan?: string;
  financialYear?: string;
  assessmentYear?: string;
  grossSalary?: number;
  standardDeduction?: number;
  chapterViaDeductions?: number;
  taxDeductedAtSource?: number;
  taxableIncome?: number;
  panMatchStatus: 'matches_vault' | 'differs_from_vault' | 'not_found' | 'not_checked';
};

const expectedSignalsByType: Record<string, { signals: string[]; insight: string }> = {
  form16: {
    signals: ['employer TAN', 'gross salary', 'taxable income', 'TDS'],
    insight:
      'Form 16 stored. ARTH will ask for confirmation before using parsed values.',
  },
  rentReceipts: {
    signals: ['rent amount', 'landlord details', 'rental period'],
    insight: 'Rent proof stored for HRA or rent deduction readiness.',
  },
  investment80c: {
    signals: ['ELSS', 'PPF', 'EPF', 'LIC', 'tuition fee', 'home loan principal'],
    insight: '80C proof stored for deduction readiness.',
  },
  healthInsurance80d: {
    signals: ['premium amount', 'insured person', 'policy year'],
    insight: '80D proof stored for health insurance deduction readiness.',
  },
  homeLoanCertificate: {
    signals: ['interest paid', 'principal paid', 'lender name'],
    insight: 'Home loan certificate stored for Section 24(b) and 80C review.',
  },
  educationLoanInterest: {
    signals: ['interest amount', 'repayment year', 'lender name'],
    insight: 'Education loan proof stored for Section 80E review.',
  },
  donationReceipts: {
    signals: ['80G eligibility', 'donee details', 'eligible amount'],
    insight: 'Donation receipt stored for 80G readiness.',
  },
  ais26asReview: {
    signals: ['TDS', 'TCS', 'interest', 'dividend', 'tax payments'],
    insight: 'AIS/26AS record stored for mismatch review.',
  },
  otherTaxDocument: {
    signals: ['manual review required'],
    insight: 'Tax document stored for manual readiness review.',
  },
};

export async function parseUploadedDocument(input: {
  documentType: string;
  mimeType: string;
  bytes: Buffer;
  panVaultSuffix?: PanVaultSuffix;
}): Promise<DocumentParseResult> {
  if (input.documentType !== 'form16') {
    return {
      status: 'metadata_ready',
      summary: metadataSummary(input.documentType, input.mimeType),
    };
  }

  const base = metadataSummary(input.documentType, input.mimeType);
  if (input.mimeType !== 'application/pdf') {
    return {
      status: 'unsupported',
      summary: {
        ...base,
        parser: 'deterministic-form16-v1',
        confidence: 'unsupported',
        insight:
          'Form 16 image stored securely. Deterministic parsing currently supports text PDFs only.',
        unsupportedReason: 'image_form16_parser_not_available',
      },
    };
  }

  try {
    const text = await extractPdfText(input.bytes);
    if (text.replace(/\s/g, '').length < 40) {
      return unsupportedTextPdf(base, 'no_extractable_text');
    }

    const parsed = parseForm16Text(text, input.panVaultSuffix ?? null);
    const fieldCount = countParsedFields(parsed);
    if (fieldCount < 2) {
      return unsupportedTextPdf(base, 'form16_fields_not_detected');
    }

    return {
      status: 'needs_confirmation',
      summary: {
        ...base,
        parser: 'deterministic-form16-v1',
        llmUsed: false,
        confidence: confidenceLabel(fieldCount),
        insight:
          'Form 16 text parsed. Review and confirm these values before ARTH uses them for filing readiness.',
        extractedFields: parsed,
        confirmationStatus: 'pending',
        reviewRequired: true,
      },
    };
  } catch (error) {
    const reason = error instanceof PasswordException
      ? 'password_protected_pdf'
      : 'pdf_text_extraction_failed';
    return unsupportedTextPdf(base, reason);
  }
}

export function metadataSummary(documentType: string, mimeType: string) {
  const configured = expectedSignalsByType[documentType] ?? expectedSignalsByType.otherTaxDocument;
  return {
    parser: 'deterministic-metadata-v1',
    llmUsed: false,
    confidence: 'metadata_only',
    mimeType,
    expectedSignals: configured.signals,
    insight: configured.insight,
  };
}

export function parseForm16Text(text: string, panVaultSuffix: PanVaultSuffix): ParsedForm16Fields {
  const normalized = normalizeText(text);
  const pan = extractEmployeePan(normalized);
  return compactFields({
    employerName: extractEmployerName(normalized),
    employerTan: findFirst(normalized, /\b([A-Z]{4}[0-9]{5}[A-Z])\b/),
    financialYear: findFirst(normalized, /financial year\s*[:\-]?\s*([0-9]{4}\s*[-/]\s*[0-9]{2,4})/i),
    assessmentYear: findFirst(normalized, /assessment year\s*[:\-]?\s*([0-9]{4}\s*[-/]\s*[0-9]{2,4})/i),
    grossSalary: findMoney(normalized, [
      /gross salary(?:\s*\(a\))?\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /gross total salary\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
    standardDeduction: findMoney(normalized, [
      /standard deduction\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
    chapterViaDeductions: findMoney(normalized, [
      /chapter vi[-\s]?a(?: deductions?)?\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /aggregate of deductible amount under chapter vi[-\s]?a\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
    taxDeductedAtSource: findMoney(normalized, [
      /tax deducted at source\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /total tds\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
    taxableIncome: findMoney(normalized, [
      /taxable income\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /income chargeable under the head salaries\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /total income\s*[:\-]?\s*(?:rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
    panMatchStatus: panMatchStatus(pan, panVaultSuffix),
  });
}

function unsupportedTextPdf(
  base: Record<string, unknown>,
  reason: string,
): DocumentParseResult {
  return {
    status: 'unsupported',
    summary: {
      ...base,
      parser: 'deterministic-form16-v1',
      llmUsed: false,
      confidence: 'unsupported',
      insight:
        'Form 16 stored securely. This file needs manual review because ARTH could not extract reliable text fields.',
      unsupportedReason: reason,
      reviewRequired: true,
    },
  };
}

async function extractPdfText(bytes: Buffer): Promise<string> {
  const parser = new PDFParse({ data: new Uint8Array(bytes) });
  try {
    const result = await parser.getText();
    return result.text;
  } finally {
    await parser.destroy();
  }
}

function normalizeText(text: string): string {
  return text
    .replace(/\r/g, '\n')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{2,}/g, '\n')
    .trim();
}

function extractEmployerName(text: string): string | undefined {
  const linePatterns = [
    /(?:name and address of employer|name of employer|employer name)\s*[:\-]?\s*([^\n]+)/i,
    /employer\s*[:\-]?\s*([A-Z][A-Z0-9&.,'() -]{3,})/i,
  ];
  for (const pattern of linePatterns) {
    const match = pattern.exec(text);
    const value = cleanText(match?.[1]);
    if (value && !/[0-9]{4}\s*[-/]\s*[0-9]{2,4}/.test(value)) return value;
  }
  return undefined;
}

function findMoney(text: string, patterns: RegExp[]): number | undefined {
  for (const pattern of patterns) {
    const value = findFirst(text, pattern);
    const parsed = value ? Number.parseFloat(value.replace(/,/g, '')) : Number.NaN;
    if (Number.isFinite(parsed)) return Math.round(parsed);
  }
  return undefined;
}

function findFirst(text: string, pattern: RegExp): string | undefined {
  return cleanText(pattern.exec(text)?.[1]);
}

function extractEmployeePan(text: string): string | undefined {
  const employeePatterns = [
    /(?:employee|deductee)(?:'s)?\s+pan\s*[:\-]?\s*([a-z]{5}[0-9]{4}[a-z])/i,
    /pan\s+of\s+(?:the\s+)?(?:employee|deductee)\s*[:\-]?\s*([a-z]{5}[0-9]{4}[a-z])/i,
  ];
  for (const pattern of employeePatterns) {
    const match = findFirst(text, pattern);
    if (match) return match.toUpperCase();
  }
  return findFirst(text, /\b([a-z]{5}[0-9]{4}[a-z])\b/i)?.toUpperCase();
}

function cleanText(value: string | undefined): string | undefined {
  const cleaned = value?.replace(/\s+/g, ' ').trim();
  return cleaned && cleaned.length <= 120 ? cleaned : undefined;
}

function panMatchStatus(
  pan: string | undefined,
  panVaultSuffix: PanVaultSuffix,
): ParsedForm16Fields['panMatchStatus'] {
  if (!pan) return 'not_found';
  if (!panVaultSuffix) return 'not_checked';
  const normalizedPan = pan.toUpperCase();
  const last4 = normalizedPan.slice(5, 9);
  const lastChar = normalizedPan.slice(9);
  return last4 === panVaultSuffix.last4 && lastChar === panVaultSuffix.lastChar
    ? 'matches_vault'
    : 'differs_from_vault';
}

function compactFields(fields: ParsedForm16Fields): ParsedForm16Fields {
  return Object.fromEntries(
    Object.entries(fields).filter(([, value]) => value !== undefined && value !== ''),
  ) as ParsedForm16Fields;
}

function countParsedFields(fields: ParsedForm16Fields): number {
  return Object.entries(fields)
    .filter(([key, value]) => key !== 'panMatchStatus' && value !== undefined && value !== '')
    .length;
}

function confidenceLabel(fieldCount: number): 'low' | 'medium' | 'high' {
  if (fieldCount >= 6) return 'high';
  if (fieldCount >= 4) return 'medium';
  return 'low';
}
