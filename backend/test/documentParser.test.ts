import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { parseUploadedDocument } from '../src/documentParser.js';

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
});

describe('payslip interpretation', () => {
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
