import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { parsePayslipText, parseUploadedDocument } from '../src/documentParser.js';

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
      assert.equal(result.summary.parser, 'gemini-payslip-v1');
      assert.equal(result.summary.reviewRequired, true);
      assert.equal(result.summary.llmUsed, false);
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
});
