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
                questionsForUser: [],
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
      assert.deepEqual(properties?.employerName, {
        type: 'string',
        nullable: true,
      });
      assert.deepEqual(properties?.annualCtc, {
        type: 'number',
        nullable: true,
      });
      assert.equal(requestBody?.store, false);
      assert.equal(result.status, 'needs_confirmation');
      assert.equal(result.summary.llmUsed, true);
    } finally {
      globalThis.fetch = previousFetch;
      if (previousKey) process.env.GEMINI_API_KEY = previousKey;
      else delete process.env.GEMINI_API_KEY;
    }
  });
});
