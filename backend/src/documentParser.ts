import { PasswordException, PDFParse } from 'pdf-parse';
import {
  interpretOfferLetter,
  interpretPayslip,
  type PayslipInterpretation,
} from './geminiInterpreter.js';
import type { SpendGuard } from './geminiStructuredCall.js';
import { digitizeWithSarvam } from './sarvamDocumentService.js';

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

type ExplicitPayslipFields = Pick<
  PayslipInterpretation,
  | 'employerName'
  | 'employeeName'
  | 'payPeriod'
  | 'paymentDate'
  | 'attendance'
  | 'grossEarnings'
  | 'totalDeductions'
  | 'netSalary'
>;

const expectedSignalsByType: Record<string, { signals: string[]; insight: string }> = {
  offerLetter: {
    signals: ['employer', 'role', 'fixed pay', 'variable pay', 'benefits'],
    insight: 'Offer letter stored. Review every interpreted component before ARTH tracks it.',
  },
  form16: {
    signals: ['employer TAN', 'gross salary', 'taxable income', 'TDS'],
    insight:
      'Form 16 stored. ARTH will ask for confirmation before using parsed values.',
  },
  payslip: {
    signals: ['pay period', 'payable days', 'earnings', 'deductions', 'net salary'],
    insight: 'Payslip stored. Review each extracted salary line before reconciliation.',
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
  ocrText?: string;
  panVaultSuffix?: PanVaultSuffix;
  /// The budget this parse spends from. Required, with no default, so that no
  /// upload path can reach a paid model without being metered.
  spendGuard: SpendGuard;
}): Promise<DocumentParseResult> {
  if (input.documentType === 'payslip') {
    const base = metadataSummary(input.documentType, input.mimeType);
    let pdfText: string | undefined;
    if (input.mimeType === 'application/pdf') {
      try {
        pdfText = await extractPdfText(input.bytes);
      } catch {
        // Scanned or locked PDFs may not expose embedded text.
      }
    }
    const sarvam = await digitizeWithSarvam({
      bytes: input.bytes,
      mimeType: input.mimeType,
    });
    const documentText = combinePayslipTextSources({
      sarvam: sarvam?.text,
      pdf: pdfText,
      device: input.ocrText,
    });
    const interpretation = documentText
      ? await interpretPayslip({ documentText, spendGuard: input.spendGuard })
      : await interpretPayslip({
          bytes: input.bytes,
          mimeType: input.mimeType,
          spendGuard: input.spendGuard,
        });
    if (interpretation) {
      const explicitFields = documentText
        ? parseExplicitPayslipFields(documentText)
        : null;
      const checked = withPayslipArithmeticChecks(
        supplementExplicitPayslipFields(interpretation, explicitFields),
      );
      return {
        status: 'needs_confirmation',
        summary: {
          ...base,
          parser: sarvam ? 'sarvam-gemini-payslip-v2' : 'gemini-payslip-v2',
          ...(sarvam ? {
            documentProvider: 'sarvam',
            providerJobId: sarvam.jobId,
          } : {}),
          textSources: availableTextSources({
            sarvam: sarvam?.text,
            pdf: pdfText,
            device: input.ocrText,
          }),
          model: process.env.GEMINI_MODEL || 'gemini-3.6-flash',
          llmUsed: true,
          confidence: checked.warnings.length === 0 ? 'medium' : 'low',
          insight:
            'The full payslip was digitized and normalized. Confirm every earning and deduction before reconciliation.',
          extractedFields: checked,
          confirmationStatus: 'pending',
          reviewRequired: true,
        },
      };
    }

    const fallbackText = sarvam?.text ?? pdfText ?? input.ocrText;
    const fallback = fallbackText ? parsePayslipText(fallbackText) : null;
    if (fallback) {
      const checked = withPayslipArithmeticChecks(fallback);
      return {
        status: 'needs_confirmation',
        summary: {
          ...base,
          parser: sarvam
            ? 'sarvam-deterministic-payslip-v2'
            : 'deterministic-payslip-v2',
          ...(sarvam ? {
            documentProvider: 'sarvam',
            providerJobId: sarvam.jobId,
          } : {}),
          textSources: availableTextSources({
            sarvam: sarvam?.text,
            pdf: pdfText,
            device: input.ocrText,
          }),
          llmUsed: false,
          confidence: 'low',
          insight:
            'Gemini was unavailable. ARTH used a limited fallback parser, so check every row.',
          extractedFields: checked,
          confirmationStatus: 'pending',
          reviewRequired: true,
        },
      };
    }

    if (!interpretation) {
      return {
        status: 'metadata_ready',
        summary: {
          ...base,
          parser: 'gemini-payslip-v2',
          model: process.env.GEMINI_MODEL || 'gemini-3.6-flash',
          insight: 'Payslip stored securely. AI extraction is unavailable, so manual review is required.',
          reviewRequired: true,
        },
      };
    }
  }

  if (input.documentType === 'offerLetter') {
    const base = metadataSummary(input.documentType, input.mimeType);
    const sarvam = await digitizeWithSarvam({
      bytes: input.bytes,
      mimeType: input.mimeType,
    });
    const interpretation = sarvam
      ? await interpretOfferLetter({
          documentText: sarvam.text,
          spendGuard: input.spendGuard,
        })
      : await interpretOfferLetter({
          bytes: input.bytes,
          mimeType: input.mimeType,
          spendGuard: input.spendGuard,
        });
    if (!interpretation) {
      return {
        status: 'metadata_ready',
        summary: {
          ...base,
          parser: 'gemini-offer-letter-v1',
          model: 'gemini-3.6-flash',
          insight: 'Offer letter stored securely. AI interpretation is unavailable, so manual review is required.',
          reviewRequired: true,
        },
      };
    }
    if (looksLikePayslip(interpretation)) {
      const payslip = sarvam
        ? await interpretPayslip({
            documentText: sarvam.text,
            spendGuard: input.spendGuard,
          })
        : await interpretPayslip({
            bytes: input.bytes,
            mimeType: input.mimeType,
            spendGuard: input.spendGuard,
          });
      if (payslip) {
        const checked = withPayslipArithmeticChecks(payslip);
        return {
          status: 'needs_confirmation',
          summary: {
            ...base,
            parser: sarvam ? 'sarvam-gemini-payslip-v1' : 'gemini-payslip-v1',
            ...(sarvam ? {
              documentProvider: 'sarvam',
              providerJobId: sarvam.jobId,
            } : {}),
            model: process.env.GEMINI_MODEL || 'gemini-3.6-flash',
            llmUsed: true,
            detectedDocumentType: 'payslip',
            confidence: checked.warnings.length === 0 ? 'medium' : 'low',
            insight: 'This file is a payslip, not an offer letter. Review the monthly pay details before ARTH uses them.',
            extractedFields: checked,
            confirmationStatus: 'pending',
            reviewRequired: true,
          },
        };
      }
    }
    return {
      status: 'needs_confirmation',
      summary: {
        ...base,
        parser: sarvam ? 'sarvam-gemini-offer-letter-v1' : 'gemini-offer-letter-v1',
        ...(sarvam ? {
          documentProvider: 'sarvam',
          providerJobId: sarvam.jobId,
        } : {}),
        model: 'gemini-3.6-flash',
        llmUsed: true,
        confidence: interpretation.warnings.length === 0 ? 'medium' : 'low',
        insight: 'Offer letter interpreted. Confirm every component before ARTH uses it.',
        extractedFields: interpretation,
        confirmationStatus: 'pending',
        reviewRequired: true,
      },
    };
  }

  // Proof documents (rent receipts, 80C/80D/home-loan/education/donation
  // proofs): extract a few structured amounts so the diagnostic can pre-fill
  // the matching question. Values always land as `needs_confirmation` because
  // receipt OCR is noisy — the user reviews before they are used.
  if (PROOF_DOCUMENT_TYPES.has(input.documentType)) {
    const base = metadataSummary(input.documentType, input.mimeType);
    let text: string | undefined;
    let parser = `deterministic-${input.documentType}-v1`;
    let providerJobId: string | undefined;

    if (input.mimeType === 'application/pdf') {
      try {
        text = await extractPdfText(input.bytes);
      } catch {
        // Scanned/locked PDF — fall through to Sarvam / device OCR.
      }
    }
    if (!text || text.replace(/\s/g, '').length < 20) {
      text = input.ocrText ?? text;
    }
    if (!text || text.replace(/\s/g, '').length < 20) {
      const sarvam = await digitizeWithSarvam({
        bytes: input.bytes,
        mimeType: input.mimeType,
      });
      if (sarvam) {
        text = sarvam.text;
        parser = `sarvam-deterministic-${input.documentType}-v1`;
        providerJobId = sarvam.jobId;
      }
    }

    if (text && text.replace(/\s/g, '').length >= 20) {
      const parsed = parseProofDocumentText(input.documentType, text);
      const fieldCount = countParsedFields(parsed);
      if (fieldCount >= 1) {
        return {
          status: 'needs_confirmation',
          summary: {
            ...base,
            parser,
            ...(providerJobId
              ? { documentProvider: 'sarvam', providerJobId }
              : {}),
            llmUsed: false,
            confidence: 'low',
            insight:
              'ARTH read an amount from this proof. Confirm it before it pre-fills your diagnostic.',
            extractedFields: parsed,
            confirmationStatus: 'pending',
            reviewRequired: true,
          },
        };
      }
    }

    return {
      status: 'metadata_ready',
      summary: base,
    };
  }

  if (input.documentType !== 'form16') {
    return {
      status: 'metadata_ready',
      summary: metadataSummary(input.documentType, input.mimeType),
    };
  }

  const base = metadataSummary(input.documentType, input.mimeType);
  let text: string | undefined;
  let parser = 'deterministic-form16-v1';
  let providerJobId: string | undefined;
  let failureReason = input.mimeType === 'application/pdf'
    ? 'no_extractable_text'
    : 'image_form16_parser_not_available';

  if (input.mimeType === 'application/pdf') {
    try {
      text = await extractPdfText(input.bytes);
    } catch (error) {
      failureReason = error instanceof PasswordException
        ? 'password_protected_pdf'
        : 'pdf_text_extraction_failed';
    }
  }

  if (!text || text.replace(/\s/g, '').length < 40) {
    const sarvam = await digitizeWithSarvam({
      bytes: input.bytes,
      mimeType: input.mimeType,
    });
    if (sarvam) {
      text = sarvam.text;
      parser = 'sarvam-deterministic-form16-v1';
      providerJobId = sarvam.jobId;
    }
  }

  if (!text || text.replace(/\s/g, '').length < 40) {
    return unsupportedTextPdf(base, failureReason);
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
      parser,
      ...(providerJobId ? {
        documentProvider: 'sarvam',
        providerJobId,
      } : {}),
      llmUsed: false,
      confidence: confidenceLabel(fieldCount),
      insight:
        'Form 16 text parsed. Review and confirm these values before ARTH uses them for filing readiness.',
      extractedFields: parsed,
      confirmationStatus: 'pending',
      reviewRequired: true,
    },
  };
}

function looksLikePayslip(interpretation: {
  annualCtc: number | null;
  fixedAnnualPay: number | null;
  variableAnnualPay: number | null;
  components: Array<{ frequency: string; annualAmount: number | null }>;
  warnings: string[];
  questionsForUser: string[];
}): boolean {
  const hasAnnualValue = [
    interpretation.annualCtc,
    interpretation.fixedAnnualPay,
    interpretation.variableAnnualPay,
  ].some((value) => value != null);
  if (hasAnnualValue) return false;

  const monthlyRows = interpretation.components.filter(
    (component) => component.frequency === 'monthly',
  ).length;
  const explanation = [
    ...interpretation.warnings,
    ...interpretation.questionsForUser,
  ].join(' ').toLowerCase();
  return explanation.includes('payslip') ||
    (monthlyRows >= 2 && explanation.includes('monthly'));
}

function withPayslipArithmeticChecks(
  payslip: PayslipInterpretation,
): PayslipInterpretation {
  const warnings = [...payslip.warnings];
  const earnings = deduplicatePayrollRows(payslip.earnings, 'earning', warnings);
  const deductions = deduplicatePayrollRows(payslip.deductions, 'deduction', warnings);
  const earningsSum = earnings.reduce((sum, row) => sum + row.amount, 0);
  const deductionsSum = deductions.reduce((sum, row) => sum + row.amount, 0);
  const tolerance = 1;

  if (payslip.grossEarnings != null &&
      Math.abs(earningsSum - payslip.grossEarnings) > tolerance) {
    warnings.push('Earning line items do not match the printed gross earnings.');
  }
  if (payslip.totalDeductions != null &&
      Math.abs(deductionsSum - payslip.totalDeductions) > tolerance) {
    warnings.push('Deduction line items do not match the printed total deductions.');
  }
  if (payslip.grossEarnings != null &&
      payslip.totalDeductions != null &&
      payslip.netSalary != null &&
      Math.abs(
        payslip.grossEarnings - payslip.totalDeductions - payslip.netSalary,
      ) > tolerance) {
    warnings.push('Gross earnings minus deductions does not match the printed net salary.');
  }

  return {
    ...payslip,
    earnings,
    deductions,
    warnings: [...new Set(warnings)].slice(0, 20),
  };
}

function supplementExplicitPayslipFields(
  interpretation: PayslipInterpretation,
  explicit: ExplicitPayslipFields | null,
): PayslipInterpretation {
  if (!explicit) return interpretation;

  return {
    ...interpretation,
    employerName: interpretation.employerName ?? explicit.employerName,
    employeeName: interpretation.employeeName ?? explicit.employeeName,
    payPeriod: interpretation.payPeriod ?? explicit.payPeriod,
    paymentDate: interpretation.paymentDate ?? explicit.paymentDate,
    attendance: {
      actualPayableDays: interpretation.attendance.actualPayableDays
        ?? explicit.attendance.actualPayableDays,
      totalWorkingDays: interpretation.attendance.totalWorkingDays
        ?? explicit.attendance.totalWorkingDays,
      lossOfPayDays: interpretation.attendance.lossOfPayDays
        ?? explicit.attendance.lossOfPayDays,
      daysPayable: interpretation.attendance.daysPayable
        ?? explicit.attendance.daysPayable,
    },
    grossEarnings: interpretation.grossEarnings ?? explicit.grossEarnings,
    totalDeductions: interpretation.totalDeductions
      ?? explicit.totalDeductions,
    netSalary: interpretation.netSalary ?? explicit.netSalary,
  };
}

function combinePayslipTextSources(sources: {
  sarvam?: string;
  pdf?: string;
  device?: string;
}): string | undefined {
  const sections: Array<[string, string | undefined]> = [
    ['SARVAM FULL DOCUMENT', sources.sarvam],
    ['EMBEDDED PDF TEXT', sources.pdf],
    ['ON DEVICE OCR', sources.device],
  ];
  const combined = sections
    .filter((entry): entry is [string, string] =>
      typeof entry[1] === 'string' && entry[1].trim().length > 0)
    .map(([label, text]) => `--- ${label} ---\n${text.trim()}`)
    .join('\n\n');
  return combined ? combined.slice(0, 100_000) : undefined;
}

function availableTextSources(sources: {
  sarvam?: string;
  pdf?: string;
  device?: string;
}): string[] {
  return Object.entries(sources)
    .filter(([, text]) => typeof text === 'string' && text.trim().length > 0)
    .map(([source]) => source);
}

type PayrollRow = PayslipInterpretation['earnings'][number]
  | PayslipInterpretation['deductions'][number];

export function deduplicatePayrollRows<T extends PayrollRow>(
  rows: T[],
  section: 'earning' | 'deduction',
  warnings: string[] = [],
): T[] {
  const result: T[] = [];
  const exact = new Set<string>();
  const amountsByKey = new Map<string, Set<number>>();

  for (const row of rows) {
    const canonicalKey = canonicalPayrollKey(row, section);
    const normalized = { ...row, canonicalKey } as T;
    const amount = Number(row.amount.toFixed(2));
    const exactKey = `${canonicalKey}:${amount}`;
    if (exact.has(exactKey)) continue;

    const existingAmounts = amountsByKey.get(canonicalKey);
    if (existingAmounts && !existingAmounts.has(amount)) {
      warnings.push(
        `Multiple ${humanizeCanonicalKey(canonicalKey)} rows have different amounts. Confirm each one.`,
      );
    }
    exact.add(exactKey);
    (existingAmounts ?? new Set<number>()).add(amount);
    amountsByKey.set(canonicalKey, existingAmounts ?? new Set([amount]));
    result.push(normalized);
  }
  return result;
}

function canonicalPayrollKey(
  row: PayrollRow,
  section: 'earning' | 'deduction',
): string {
  const label = row.label.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  if (section === 'earning') {
    if (/\b(hra|house rent allowance)\b/.test(label)) return 'house_rent_allowance';
    if (/\bbasic\b/.test(label)) return 'basic_pay';
  } else {
    if (/\b(vpf|voluntary provident)\b/.test(label)) return 'voluntary_provident_fund';
    if (/\b(cpf pc|epf|employee provident|provident fund|pf contribution)\b/.test(label)) {
      return 'employee_provident_fund';
    }
    if (/\b(itax|income tax|tds)\b/.test(label)) return 'income_tax';
    if (/\b(ptax|professional tax)\b/.test(label)) return 'professional_tax';
    if (/\b(hrent|house rent recovery|rent recovery)\b/.test(label)) {
      return 'house_rent_recovery';
    }
    if (/\blic\b/.test(label)) return 'life_insurance';
  }
  const supplied = 'canonicalKey' in row ? row.canonicalKey : '';
  return slug(supplied || row.label);
}

function slug(value: string): string {
  return value
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80) || 'unknown';
}

function humanizeCanonicalKey(value: string): string {
  return value.replace(/_/g, ' ');
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

/** Proof document types that carry a structured amount worth pre-filling. */
export const PROOF_DOCUMENT_TYPES = new Set<string>([
  'rentReceipts',
  'investment80c',
  'healthInsurance80d',
  'homeLoanCertificate',
  'educationLoanInterest',
  'donationReceipts',
]);

const _amt = '([0-9][0-9,]*(?:\\.[0-9]{1,2})?)';
const _cur = '(?:rs\\.?|inr|₹)\\s*';

/**
 * Extracts a small set of structured amounts from a proof document's text.
 * Heuristic and lossy by nature (receipts vary wildly), so results are always
 * surfaced as `needs_confirmation`. Emits numeric keys the Flutter profile
 * prefill understands (monthlyRent, healthInsuranceSelfPremium, …).
 */
export function parseProofDocumentText(
  documentType: string,
  rawText: string,
): Record<string, number> {
  const text = normalizeText(rawText);
  const money = (patterns: RegExp[]) => findMoney(text, patterns);
  const interestPatterns = [new RegExp(`interest[^0-9]{0,20}${_cur}${_amt}`, 'i')];

  switch (documentType) {
    case 'rentReceipts':
      return compactNumeric({
        monthlyRent: money([
          new RegExp(`monthly rent[^0-9]{0,12}${_cur}${_amt}`, 'i'),
          new RegExp(`rent[^0-9]{0,12}${_cur}${_amt}\\s*(?:/|per\\s*)?month`, 'i'),
          new RegExp(`rent(?:\\s*(?:paid|of|amount|received))?[^0-9]{0,12}${_cur}${_amt}`, 'i'),
        ]),
      });
    case 'healthInsurance80d':
      return compactNumeric({
        healthInsuranceSelfPremium: money([
          new RegExp(`(?:premium|amount paid)[^0-9]{0,15}${_cur}${_amt}`, 'i'),
          new RegExp(`${_cur}${_amt}\\s*(?:as|towards)?\\s*premium`, 'i'),
        ]),
      });
    case 'homeLoanCertificate':
      return compactNumeric({
        homeLoanInterest: money(interestPatterns),
        homeLoanPrincipal: money([
          new RegExp(`principal[^0-9]{0,20}${_cur}${_amt}`, 'i'),
        ]),
      });
    case 'educationLoanInterest':
      return compactNumeric({educationLoanInterest: money(interestPatterns)});
    case 'donationReceipts':
      return compactNumeric({
        donationAmount: money([
          new RegExp(`(?:donation|donated|contribution|amount)[^0-9]{0,15}${_cur}${_amt}`, 'i'),
        ]),
      });
    case 'investment80c':
      return compactNumeric({
        invested80C: money([
          new RegExp(`(?:total|invested|investment|amount|contribution)[^0-9]{0,15}${_cur}${_amt}`, 'i'),
          new RegExp(`${_cur}${_amt}`, 'i'),
        ]),
      });
    default:
      return {};
  }
}

function compactNumeric(
  fields: Record<string, number | undefined>,
): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (typeof value === 'number' && value > 0) out[key] = value;
  }
  return out;
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

export function parsePayslipText(text: string): PayslipInterpretation | null {
  const normalized = normalizeText(text);
  if (normalized.replace(/\s/g, '').length < 40) return null;
  const explicit = parseExplicitPayslipFields(normalized);

  const earnings = extractPayslipRows(
    normalized,
    'earnings',
  ) as PayslipInterpretation['earnings'];
  const deductions = extractPayslipRows(
    normalized,
    'deductions',
  ) as PayslipInterpretation['deductions'];

  const signalCount = earnings.length + deductions.length +
    (explicit.grossEarnings == null ? 0 : 1) +
    (explicit.totalDeductions == null ? 0 : 1) +
    (explicit.netSalary == null ? 0 : 1);
  if (signalCount < 3) return null;

  return {
    employerName: explicit.employerName,
    employeeName: explicit.employeeName,
    payPeriod: explicit.payPeriod,
    paymentDate: explicit.paymentDate,
    currency: 'INR',
    attendance: explicit.attendance,
    earnings,
    deductions,
    cumulative: [],
    grossEarnings: explicit.grossEarnings,
    totalDeductions: explicit.totalDeductions,
    netSalary: explicit.netSalary,
    warnings: [],
    questionsForUser: [
      ...(earnings.length === 0 ? ['Confirm earning line items manually.'] : []),
      ...(deductions.length === 0 ? ['Confirm deduction line items manually.'] : []),
    ],
  };
}

function parseExplicitPayslipFields(text: string): ExplicitPayslipFields {
  const normalized = normalizeText(text);
  return {
    employerName: extractPayslipEmployer(normalized) ?? null,
    employeeName: extractPayslipEmployee(normalized) ?? null,
    payPeriod: extractPayPeriod(normalized) ?? null,
    paymentDate: extractPaymentDate(normalized) ?? null,
    attendance: {
      actualPayableDays: findNumberAfterLabel(normalized, /actual payable days/i),
      totalWorkingDays: findNumberAfterLabel(normalized, /total working days/i),
      lossOfPayDays: findNumberAfterLabel(normalized, /loss of pay days/i),
      daysPayable: findNumberAfterLabel(normalized, /days payable/i),
    },
    grossEarnings: findMoneyDecimal(normalized, [
      /total earnings(?:\s*\([a-z]\))?\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /gross earnings\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /taxable gross pay\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /gross pay\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
    totalDeductions: findMoneyDecimal(normalized, [
      /total taxes\s*&\s*deductions(?:\s*\([a-z]\))?\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /total deductions(?:\s*\([a-z]\))?\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /non[\s-]*taxable deductions\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /total recoveries\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
    netSalary: findMoneyDecimal(normalized, [
      /net salary payable(?:\s*\([^)]+\))?\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /net salary\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
      /net pay\s*[:\-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    ]),
  };
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

function findMoneyDecimal(text: string, patterns: RegExp[]): number | null {
  for (const pattern of patterns) {
    const value = findFirst(text, pattern);
    const parsed = value ? Number.parseFloat(value.replace(/,/g, '')) : Number.NaN;
    if (Number.isFinite(parsed)) return Number(parsed.toFixed(2));
  }
  return null;
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

function extractPayslipRows(
  text: string,
  section: 'earnings' | 'deductions',
): Array<{
  label: string;
  amount: number;
  classification: string;
  confidence: 'high' | 'medium' | 'low';
}> {
  const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
  const rows: Array<{
    label: string;
    canonicalKey: string;
    amount: number;
    classification: string;
    confidence: 'high' | 'medium' | 'low';
  }> = [];
  let active = false;
  for (const line of lines) {
    if (/^(earnings|payments?\s*(?:\(taxable\))?)\b/i.test(line) ||
        /\/payments?\s*(?:\(taxable\))?/i.test(line)) {
      active = section === 'earnings';
      continue;
    }
    if (/^(taxes\s*&\s*deductions|deductions|recoveries)\b/i.test(line) ||
        /\/recoveries\b/i.test(line)) {
      active = section === 'deductions';
      continue;
    }
    if (/^(net salary|net pay|salary in words|cumulatives?)\b/i.test(line) ||
        /\/cumulatives?\b/i.test(line)) {
      active = false;
    }
    if (!active) continue;

    const match = /^([A-Za-z][A-Za-z &/().-]{1,90}?)\s+(?:rs\.?|inr|₹)?\s*(-?[0-9][0-9,]*(?:\.[0-9]{1,2})?)$/i.exec(line);
    if (!match) continue;
    const label = cleanText(match[1]);
    const amount = Number.parseFloat(match[2].replace(/,/g, ''));
    if (!label || !Number.isFinite(amount) || /^total\b/i.test(label)) continue;
    rows.push({
      label,
      canonicalKey: slug(label),
      amount: Number(amount.toFixed(2)),
      classification: section === 'earnings'
        ? classifyEarning(label)
        : classifyDeduction(label),
      confidence: 'medium',
    });
  }
  return rows.slice(0, 80);
}

function classifyEarning(label: string): PayslipInterpretation['earnings'][number]['classification'] {
  const lower = label.toLowerCase();
  if (lower.includes('basic')) return 'basic_pay';
  if (lower.includes('hra') || lower.includes('house rent')) return 'hra';
  if (lower.includes('reimbursement') || lower.includes('lta') || lower.includes('travel')) {
    return 'reimbursement';
  }
  if (lower.includes('bonus') || lower.includes('incentive')) return 'bonus';
  if (lower.includes('variable')) return 'variable_pay';
  if (lower.includes('allowance')) return 'allowance';
  return 'other';
}

function classifyDeduction(label: string): PayslipInterpretation['deductions'][number]['classification'] {
  const lower = label.toLowerCase();
  if (lower.includes('professional tax') || lower.includes('ptax')) return 'professional_tax';
  if (lower.includes('income tax') || lower.includes('tds') || lower.includes('itax')) {
    return 'income_tax';
  }
  if (lower.includes('vpf') || lower.includes('voluntary provident')) return 'voluntary_pf';
  if (lower.includes('pf') || lower.includes('provident')) return 'employee_pf';
  if (lower.includes('esi')) return 'employee_esi';
  if (lower.includes('lic') || lower.includes('insurance')) return 'insurance';
  if (lower.includes('loan')) return 'loan_repayment';
  if (lower.includes('rent')) return 'housing_recovery';
  if (lower.includes('electric') || lower.includes('water')) return 'utility_recovery';
  if (lower.includes('welfare')) return 'welfare_contribution';
  if (lower.includes('coop')) return 'cooperative_recovery';
  if (lower.includes('adjust') || lower.includes('ntax')) return 'salary_adjustment';
  return 'other';
}

function findNumberAfterLabel(text: string, label: RegExp): number | null {
  const lines = text.split('\n');
  for (const line of lines) {
    if (!label.test(line)) continue;
    const match = /([0-9]+(?:\.[0-9]+)?)(?!.*[0-9])/.exec(line);
    if (!match) return null;
    const parsed = Number.parseFloat(match[1]);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function extractPayslipEmployer(text: string): string | undefined {
  return findFirst(text, /(?:employer|company|organisation|organization)\s*(?:name)?\s*[:\-]?\s*([^\n]+)/i);
}

function extractPayslipEmployee(text: string): string | undefined {
  return findFirst(
    text,
    /(?:(?:employee|associate)\s*(?:name)?|name\/name)\s*[:\-]?\s*([^\n]+)/i,
  );
}

function extractPayPeriod(text: string): string | undefined {
  return findFirst(
    text,
    /(?:payslip for|pay period|salary month|payroll month|month)\s*[:\-]?\s*([A-Za-z]+[-\s]+[0-9]{4}|[0-9]{2}[-/][0-9]{4})/i,
  );
}

function extractPaymentDate(text: string): string | undefined {
  return findFirst(text, /(?:payment date|paid on|salary date)\s*[:\-]?\s*([0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{2,4})/i);
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

function countParsedFields(fields: Record<string, unknown>): number {
  return Object.entries(fields)
    .filter(([key, value]) => key !== 'panMatchStatus' && value !== undefined && value !== '')
    .length;
}

function confidenceLabel(fieldCount: number): 'low' | 'medium' | 'high' {
  if (fieldCount >= 6) return 'high';
  if (fieldCount >= 4) return 'medium';
  return 'low';
}
