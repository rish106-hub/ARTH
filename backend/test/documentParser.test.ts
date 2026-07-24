import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  deduplicatePayrollRows,
  parsePayslipText,
  parseUploadedDocument,
} from '../src/documentParser.js';
import { interpretPayslip } from '../src/geminiInterpreter.js';

describe('offer letter interpretation', () => {
  it('stores the document for manual review when Gemini is not configured', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    delete process.env.GEMINI_API_KEY;
    try {
      const result = await parseUploadedDocument({
        documentType: 'offerLetter',
        mimeType: 'application/pdf',
        bytes: Buffer.from('example offer letter'),
      });

      assert.equal(result.status, 'metadata_ready');
      assert.equal(result.summary.reviewRequired, true);
      assert.equal(result.summary.llmUsed, false);
    } finally {
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
    }
  });

  it('uses the generateContent nullable schema and returns fields for review', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    const previousFetch = globalThis.fetch;
    let requestBody: Record<string, any> | undefined;
    process.env.GEMINI_API_KEY = 'test-gemini-key';
    globalThis.fetch = async (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                employerName: 'Example Technologies',
                roleTitle: 'Analyst',
                currency: 'INR',
                annualCtc: 1200000,
                fixedAnnualPay: 1100000,
                variableAnnualPay: 100000,
                joiningBonus: null,
                components: [],
                warnings: [],
                questionsForUser: ['q'.repeat(300)],
              }),
            }],
          },
        }],
      }), { status: 200 });
    };

    try {
      const result = await parseUploadedDocument({
        documentType: 'offerLetter',
        mimeType: 'application/pdf',
        bytes: Buffer.from('example offer letter'),
      });

      const properties = requestBody?.generationConfig?.responseSchema?.properties;
      assert.equal(properties?.employerName.type, 'string');
      assert.equal(properties?.employerName.nullable, true);
      assert.deepEqual(properties?.annualCtc, {
        type: 'number',
        nullable: true,
      });
      assert.equal(requestBody?.store, false);
      assert.equal(result.status, 'needs_confirmation');
      assert.equal(result.summary.llmUsed, true);
      const fields = result.summary.extractedFields as {
        questionsForUser: string[];
      };
      assert.equal(fields.questionsForUser[0].length, 240);
    } finally {
      globalThis.fetch = previousFetch;
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
      else delete process.env.GEMINI_API_KEY;
    }
  });

  it('re-runs extraction as a payslip when the selected file type is wrong', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    const previousFetch = globalThis.fetch;
    let callCount = 0;
    process.env.GEMINI_API_KEY = 'test-gemini-key';
    globalThis.fetch = async () => {
      callCount += 1;
      const result = callCount === 1
        ? {
            employerName: null,
            roleTitle: null,
            currency: 'INR',
            annualCtc: null,
            fixedAnnualPay: null,
            variableAnnualPay: null,
            joiningBonus: null,
            components: [
              {
                label: 'Basic',
                annualAmount: null,
                frequency: 'monthly',
                classification: 'fixed_pay',
                confidence: 'high',
              },
              {
                label: 'HRA',
                annualAmount: null,
                frequency: 'monthly',
                classification: 'allowance',
                confidence: 'high',
              },
            ],
            warnings: ['This document contains monthly payslip details.'],
            questionsForUser: [],
          }
        : {
            employerName: 'Example Employer',
            employeeName: 'Example Employee',
            payPeriod: 'July 2026',
            paymentDate: null,
            currency: 'INR',
            attendance: {
              actualPayableDays: 30,
              totalWorkingDays: 29,
              lossOfPayDays: 0,
              daysPayable: 29,
            },
            earnings: [{
              label: 'Basic',
              amount: 19333.33,
              classification: 'basic_pay',
              confidence: 'high',
            }],
            deductions: [{
              label: 'Professional Tax',
              amount: 200,
              classification: 'professional_tax',
              confidence: 'high',
            }],
            grossEarnings: 19333.33,
            totalDeductions: 200,
            netSalary: 19133.33,
            warnings: [],
            questionsForUser: [],
          };
      return new Response(JSON.stringify({
        candidates: [{ content: { parts: [{ text: JSON.stringify(result) }] } }],
      }), { status: 200 });
    };

    try {
      const parsed = await parseUploadedDocument({
        documentType: 'offerLetter',
        mimeType: 'image/jpeg',
        bytes: Buffer.from('example payslip'),
      });

      assert.equal(callCount, 2);
      assert.equal(parsed.status, 'needs_confirmation');
      assert.equal(parsed.summary.parser, 'gemini-payslip-v1');
      assert.equal(parsed.summary.detectedDocumentType, 'payslip');
      const fields = parsed.summary.extractedFields as { netSalary: number };
      assert.equal(fields.netSalary, 19133.33);
    } finally {
      globalThis.fetch = previousFetch;
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
      else delete process.env.GEMINI_API_KEY;
    }
  });
});

describe('payslip interpretation', () => {
  it('gives Gemini Sarvam text without attaching the original file again', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    const previousFetch = globalThis.fetch;
    let requestBody: Record<string, any> | undefined;
    process.env.GEMINI_API_KEY = 'test-gemini-key';
    globalThis.fetch = async (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                employerName: 'Example Employer',
                employeeName: 'Example Employee',
                payPeriod: 'May 2023',
                paymentDate: null,
                currency: 'INR',
                attendance: {
                  actualPayableDays: null,
                  totalWorkingDays: null,
                  lossOfPayDays: null,
                  daysPayable: null,
                },
                earnings: [],
                deductions: [],
                cumulative: [],
                grossEarnings: 109412,
                totalDeductions: 50969,
                netSalary: 58443,
                warnings: [],
                questionsForUser: [],
              }),
            }],
          },
        }],
      }), { status: 200 });
    };

    try {
      const result = await interpretPayslip({
        documentText: '# Sarvam Markdown\nNET PAY 58443',
      });
      assert.ok(result);
      const parts = requestBody?.contents?.[0]?.parts as Array<
        { text?: string; inlineData?: unknown }
      >;
      assert.match(parts[1].text ?? '', /Sarvam Markdown/);
      assert.equal(parts.some((part) => part.inlineData != null), false);
      assert.equal(requestBody?.store, false);
    } finally {
      globalThis.fetch = previousFetch;
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
      else delete process.env.GEMINI_API_KEY;
    }
  });

  it('sends full Sarvam output to Gemini for final normalization', async () => {
    const previousSarvamKey = process.env.SARVAM_API_KEY;
    const previousGeminiKey = process.env.GEMINI_API_KEY;
    const previousFetch = globalThis.fetch;
    process.env.SARVAM_API_KEY = 'test-sarvam-key';
    process.env.GEMINI_API_KEY = 'test-gemini-key';
    globalThis.fetch = async (input, init) => {
      const url = String(input);
      if (url.includes('generativelanguage.googleapis.com')) {
        const request = JSON.parse(String(init?.body));
        const parts = request.contents[0].parts as Array<{ text?: string }>;
        assert.match(parts[1].text ?? '', /SARVAM FULL DOCUMENT/);
        assert.match(parts[1].text ?? '', /CPF PC 11022/);
        return new Response(JSON.stringify({
          candidates: [{
            content: {
              parts: [{
                text: JSON.stringify({
                  employerName: 'SAIL',
                  employeeName: 'EXAMPLE EMPLOYEE',
                  payPeriod: 'MAY-2023',
                  paymentDate: null,
                  currency: 'INR',
                  attendance: {
                    actualPayableDays: null,
                    totalWorkingDays: null,
                    lossOfPayDays: null,
                    daysPayable: null,
                  },
                  earnings: [
                    {
                      label: 'BASIC',
                      canonicalKey: 'basic_pay',
                      amount: 66703,
                      classification: 'basic_pay',
                      confidence: 'high',
                    },
                    {
                      label: 'DA',
                      canonicalKey: 'dearness_allowance',
                      amount: 25147,
                      classification: 'allowance',
                      confidence: 'high',
                    },
                    {
                      label: 'PERKS',
                      canonicalKey: 'perks',
                      amount: 15877,
                      classification: 'allowance',
                      confidence: 'high',
                    },
                  ],
                  deductions: [
                    {
                      label: 'CPF PC',
                      canonicalKey: 'employee_provident_fund',
                      amount: 11022,
                      classification: 'employee_pf',
                      confidence: 'high',
                    },
                    {
                      label: 'VPF',
                      canonicalKey: 'voluntary_provident_fund',
                      amount: 25000,
                      classification: 'voluntary_pf',
                      confidence: 'high',
                    },
                    {
                      label: 'ITAX',
                      canonicalKey: 'income_tax',
                      amount: 11059,
                      classification: 'income_tax',
                      confidence: 'high',
                    },
                  ],
                  cumulative: [],
                  grossEarnings: 109412,
                  totalDeductions: 50969,
                  netSalary: 58443,
                  warnings: [],
                  questionsForUser: [],
                }),
              }],
            },
          }],
        }), { status: 200 });
      }
      if (url.endsWith('/doc-digitization/job/v1')) {
        return new Response(JSON.stringify({
          job_id: 'job-payslip',
          job_state: 'Accepted',
        }), { status: 202 });
      }
      if (url.endsWith('/upload-files')) {
        return new Response(JSON.stringify({
          upload_urls: {
            'document-images.zip': 'https://upload.example/payslip.zip',
          },
        }), { status: 200 });
      }
      if (url === 'https://upload.example/payslip.zip') {
        return new Response(null, { status: 200 });
      }
      if (url.endsWith('/job-payslip/start')) {
        return new Response(JSON.stringify({
          job_id: 'job-payslip',
          job_state: 'Accepted',
        }), { status: 202 });
      }
      if (url.endsWith('/job-payslip/status')) {
        return new Response(JSON.stringify({
          job_id: 'job-payslip',
          job_state: 'Completed',
        }), { status: 200 });
      }
      if (url.endsWith('/job-payslip/download-files')) {
        return new Response(JSON.stringify({
          download_urls: {
            'payslip.md': 'https://download.example/payslip.md',
          },
        }), { status: 200 });
      }
      if (url === 'https://download.example/payslip.md') {
        return new Response(`
          PAYSLIP FOR MAY-2023 PAID IN JUN-2023
          NAME/NAME: EXAMPLE EMPLOYEE

          PAYMENTS (TAXABLE)
          BASIC 66703
          DA 25147
          PERKS 15877
          TOTAL EARNINGS 109412

          RECOVERIES (NON-TAXABLE)
          CPF PC 11022
          VPF 25000
          ITAX 11059
          TOTAL DEDUCTIONS 50969

          NET PAY 58443
        `, { status: 200 });
      }
      throw new Error(`Unexpected URL: ${url}`);
    };

    try {
      const result = await parseUploadedDocument({
        documentType: 'payslip',
        mimeType: 'image/jpeg',
        bytes: Buffer.from('synthetic payslip image'),
      });

      assert.equal(result.status, 'needs_confirmation');
      assert.equal(result.summary.parser, 'sarvam-gemini-payslip-v2');
      assert.equal(result.summary.documentProvider, 'sarvam');
      assert.equal(result.summary.providerJobId, 'job-payslip');
      assert.equal(result.summary.llmUsed, true);
      assert.deepEqual(result.summary.textSources, ['sarvam']);
      const fields = result.summary.extractedFields as {
        grossEarnings: number;
        totalDeductions: number;
        netSalary: number;
      };
      assert.equal(fields.grossEarnings, 109412);
      assert.equal(fields.totalDeductions, 50969);
      assert.equal(fields.netSalary, 58443);
    } finally {
      globalThis.fetch = previousFetch;
      if (previousSarvamKey) process.env.SARVAM_API_KEY = previousSarvamKey;
      else delete process.env.SARVAM_API_KEY;
      if (previousGeminiKey) process.env.GEMINI_API_KEY = previousGeminiKey;
      else delete process.env.GEMINI_API_KEY;
    }
  });

  it('parses text payslip sections without Gemini', () => {
    const parsed = parsePayslipText(`
      SALARY DETAILS
      ACTUAL PAYABLE DAYS 30
      TOTAL WORKING DAYS 29
      LOSS OF PAY DAYS 0
      DAYS PAYABLE 29

      EARNINGS
      Basic 19,333.33
      HRA 7,733.33
      Special Allowance 6,122.30
      Professional Development Allowance 966.67
      Travel Reimbursement (LTA) 1,611.03
      Phone & Internet Allowance 3,000.00
      Total Earnings (A) 38,766.66

      TAXES & DEDUCTIONS
      Professional Tax 200.00
      Total Taxes & Deductions (B) 200.00

      Net Salary Payable ( A - B ) 38,567.00
    `);

    assert.ok(parsed);
    assert.equal(parsed.attendance.actualPayableDays, 30);
    assert.equal(parsed.attendance.daysPayable, 29);
    assert.equal(parsed.earnings.length, 6);
    assert.equal(parsed.earnings[0].classification, 'basic_pay');
    assert.equal(parsed.earnings[1].classification, 'hra');
    assert.equal(parsed.deductions.length, 1);
    assert.equal(parsed.deductions[0].classification, 'professional_tax');
    assert.equal(parsed.grossEarnings, 38766.66);
    assert.equal(parsed.totalDeductions, 200);
    assert.equal(parsed.netSalary, 38567);
  });

  it('captures every printed SAIL earning and recovery row', () => {
    const parsed = parsePayslipText(`
      PAYSLIP FOR MAY-2023 PAID IN JUN-2023
      NAME/NAME: RAMKRISHNA DEWAN
      TAXABLE GROSS PAY: 109412
      NON TAXABLE DEDUCTIONS: 50969
      NET PAY: 58443

      SALARY DETAILS
      PAYMENTS (TAXABLE)
      BASIC 66703
      DA 25147
      PERKS 15877
      INCENTIVE PIS 206
      INCENTIVE 243
      INCENTIVE BONUS 712
      INCENTIVE QBMS 524

      RECOVERIES (NON-TAXABLE)
      CPF PC 11022
      VPF 25000
      SESBF 1837
      ITAX 11059
      CESS 443
      PTAX 200
      FEST REC 500
      HRENT 70
      ELEC 545
      LIC 1683
      COOP 300
      PERKS NTAX -1800
      WATER CHARGES 20
      FAMILY WELFARE 90

      CUMULATIVES
      GROSS 423039
      CPF 33026
    `);

    assert.ok(parsed);
    assert.equal(parsed.earnings.length, 7);
    assert.equal(parsed.deductions.length, 14);
    assert.equal(
      parsed.earnings.reduce((sum, row) => sum + row.amount, 0),
      109412,
    );
    assert.equal(
      parsed.deductions.reduce((sum, row) => sum + row.amount, 0),
      50969,
    );
    assert.equal(
      parsed.deductions.find((row) => row.label === 'VPF')?.classification,
      'voluntary_pf',
    );
    assert.equal(
      parsed.deductions.find((row) => row.label === 'ITAX')?.classification,
      'income_tax',
    );
    assert.equal(
      parsed.deductions.find((row) => row.label === 'PTAX')?.classification,
      'professional_tax',
    );
  });

  it('keeps a payslip for manual review when Gemini is not configured', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    delete process.env.GEMINI_API_KEY;
    try {
      const result = await parseUploadedDocument({
        documentType: 'payslip',
        mimeType: 'image/png',
        bytes: Buffer.from('example payslip'),
      });

      assert.equal(result.status, 'metadata_ready');
      assert.equal(result.summary.parser, 'gemini-payslip-v2');
      assert.equal(result.summary.reviewRequired, true);
      assert.equal(result.summary.llmUsed, false);
    } finally {
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
    }
  });

  it('parses on-device OCR text from a bilingual non-standard payslip', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    delete process.env.GEMINI_API_KEY;
    try {
      const result = await parseUploadedDocument({
        documentType: 'payslip',
        mimeType: 'image/jpeg',
        bytes: Buffer.from('synthetic payslip image'),
        ocrText: `
          PAYSLIP FOR MAY-2023 PAID IN JUN-2023
          NAME/NAME: EXAMPLE EMPLOYEE
          TAXABLE GROSS PAY: 109412
          NON TAXABLE DEDUCTIONS: 50969
          NET PAY: 58443

          भुगतान/PAYMENTS (TAXABLE)
          BASIC 66703
          DA 25147
          PERKS 15877
          INCENTIVE BONUS 712

          कटौती/RECOVERIES (NON-TAXABLE)
          CPF PC 11022
          VPF 25000
          ITAX 11059
          PERKS NTAX -1800

          संचय राशि/CUMULATIVES
          GROSS 423039
          CPF 33026
        `,
      });

      assert.equal(result.status, 'needs_confirmation');
      assert.equal(result.summary.parser, 'deterministic-payslip-v2');
      assert.equal(result.summary.llmUsed, false);
      const fields = result.summary.extractedFields as Record<string, any>;
      assert.equal(fields.payPeriod, 'MAY-2023');
      assert.equal(fields.grossEarnings, 109412);
      assert.equal(fields.totalDeductions, 50969);
      assert.equal(fields.netSalary, 58443);
      assert.equal(fields.earnings.length, 4);
      assert.equal(fields.deductions.length, 4);
      assert.equal(fields.deductions[3].amount, -1800);
    } finally {
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
    }
  });

  it('separates payslip sections and flags arithmetic mismatches', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    const previousFetch = globalThis.fetch;
    let requestBody: Record<string, any> | undefined;
    process.env.GEMINI_API_KEY = 'test-gemini-key';
    globalThis.fetch = async (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                employerName: 'Example Employer',
                employeeName: 'Example Employee',
                payPeriod: 'July 2026',
                paymentDate: null,
                currency: 'INR',
                attendance: {
                  actualPayableDays: 30,
                  totalWorkingDays: 29,
                  lossOfPayDays: 0,
                  daysPayable: 29,
                },
                earnings: [
                  {
                    label: 'Basic',
                    amount: 19333.33,
                    classification: 'basic_pay',
                    confidence: 'high',
                  },
                  {
                    label: 'HRA',
                    amount: 7733.33,
                    classification: 'hra',
                    confidence: 'high',
                  },
                ],
                deductions: [{
                  label: 'Professional Tax',
                  amount: 200,
                  classification: 'professional_tax',
                  confidence: 'high',
                }],
                grossEarnings: 38766.66,
                totalDeductions: 200,
                netSalary: 38567,
                warnings: [],
                questionsForUser: [],
              }),
            }],
          },
        }],
      }), { status: 200 });
    };

    try {
      const result = await parseUploadedDocument({
        documentType: 'payslip',
        mimeType: 'image/png',
        bytes: Buffer.from('example payslip'),
      });

      const properties = requestBody?.generationConfig?.responseSchema?.properties;
      assert.equal(properties?.attendance.type, 'object');
      assert.equal(properties?.earnings.type, 'array');
      assert.equal(properties?.deductions.type, 'array');
      assert.equal(result.status, 'needs_confirmation');
      assert.equal(result.summary.llmUsed, true);
      const fields = result.summary.extractedFields as {
        attendance: { daysPayable: number };
        earnings: unknown[];
        deductions: unknown[];
        warnings: string[];
      };
      assert.equal(fields.attendance.daysPayable, 29);
      assert.equal(fields.earnings.length, 2);
      assert.equal(fields.deductions.length, 1);
      assert.ok(fields.warnings.some((warning) =>
        warning.includes('gross earnings')));
    } finally {
      globalThis.fetch = previousFetch;
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
      else delete process.env.GEMINI_API_KEY;
    }
  });

  it('uses Gemini as the final normalizer for OCR text', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    const previousSarvamKey = process.env.SARVAM_API_KEY;
    const previousFetch = globalThis.fetch;
    let requestBody: Record<string, any> | undefined;
    process.env.GEMINI_API_KEY = 'test-gemini-key';
    delete process.env.SARVAM_API_KEY;
    globalThis.fetch = async (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                employerName: 'SAIL',
                employeeName: 'Example Employee',
                payPeriod: 'May 2023',
                paymentDate: null,
                currency: 'INR',
                attendance: {
                  actualPayableDays: null,
                  totalWorkingDays: null,
                  lossOfPayDays: null,
                  daysPayable: null,
                },
                earnings: [{
                  label: 'BASIC',
                  canonicalKey: 'basic_pay',
                  amount: 66703,
                  classification: 'basic_pay',
                  confidence: 'high',
                }],
                deductions: [{
                  label: 'ITAX',
                  canonicalKey: 'income_tax',
                  amount: 11059,
                  classification: 'income_tax',
                  confidence: 'high',
                }],
                cumulative: [],
                grossEarnings: 109412,
                totalDeductions: 50969,
                netSalary: 58443,
                warnings: [],
                questionsForUser: [],
              }),
            }],
          },
        }],
      }), { status: 200 });
    };

    try {
      const result = await parseUploadedDocument({
        documentType: 'payslip',
        mimeType: 'image/jpeg',
        bytes: Buffer.from('image'),
        ocrText: 'PAYSLIP\nBASIC 66703\nITAX 11059\nNET PAY 58443',
      });

      assert.equal(result.summary.parser, 'gemini-payslip-v2');
      assert.equal(result.summary.llmUsed, true);
      assert.deepEqual(result.summary.textSources, ['device']);
      const parts = requestBody?.contents?.[0]?.parts as Array<{ text?: string }>;
      assert.match(parts[1].text ?? '', /ON DEVICE OCR/);
    } finally {
      globalThis.fetch = previousFetch;
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
      else delete process.env.GEMINI_API_KEY;
      if (previousSarvamKey) process.env.SARVAM_API_KEY = previousSarvamKey;
      else delete process.env.SARVAM_API_KEY;
    }
  });

  it('keeps dynamic deductions and removes only semantic duplicates', () => {
    const warnings: string[] = [];
    const rows = [
      {
        label: 'ITAX',
        canonicalKey: 'income_tax',
        amount: 11059,
        classification: 'income_tax' as const,
        confidence: 'high' as const,
      },
      {
        label: 'Income Tax',
        canonicalKey: 'income_tax',
        amount: 11059,
        classification: 'income_tax' as const,
        confidence: 'high' as const,
      },
      {
        label: 'CPF PC',
        canonicalKey: 'employee_provident_fund',
        amount: 11022,
        classification: 'employee_pf' as const,
        confidence: 'high' as const,
      },
      {
        label: 'VPF',
        canonicalKey: 'voluntary_provident_fund',
        amount: 25000,
        classification: 'voluntary_pf' as const,
        confidence: 'high' as const,
      },
      ...Array.from({ length: 30 }, (_, index) => ({
        label: `Custom recovery ${index + 1}`,
        canonicalKey: `custom_recovery_${index + 1}`,
        amount: index + 1,
        classification: 'other' as const,
        confidence: 'medium' as const,
      })),
    ];

    const normalized = deduplicatePayrollRows(rows, 'deduction', warnings);

    assert.equal(normalized.length, 33);
    assert.equal(
      normalized.filter((row) => row.canonicalKey === 'income_tax').length,
      1,
    );
    assert.ok(normalized.some((row) => row.canonicalKey === 'employee_provident_fund'));
    assert.ok(normalized.some((row) => row.canonicalKey === 'voluntary_provident_fund'));
    assert.deepEqual(warnings, []);
  });

  it('keeps conflicting amounts and asks the user to confirm them', () => {
    const warnings: string[] = [];
    const rows = [
      {
        label: 'House Rent Recovery',
        canonicalKey: 'house_rent_recovery',
        amount: 70,
        classification: 'housing_recovery' as const,
        confidence: 'high' as const,
      },
      {
        label: 'HRENT',
        canonicalKey: 'house_rent_recovery',
        amount: 75,
        classification: 'housing_recovery' as const,
        confidence: 'medium' as const,
      },
    ];

    const normalized = deduplicatePayrollRows(rows, 'deduction', warnings);

    assert.equal(normalized.length, 2);
    assert.match(warnings[0], /different amounts/);
  });
});
