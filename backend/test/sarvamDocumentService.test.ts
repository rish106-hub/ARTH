import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { zipSync } from 'fflate';

import { digitizeWithSarvam } from '../src/sarvamDocumentService.js';

describe('Sarvam document digitization', () => {
  it('runs the documented job pipeline and reads Markdown from the output ZIP', async () => {
    const previousKey = process.env.SARVAM_API_KEY;
    process.env.SARVAM_API_KEY = 'test-sarvam-key';
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const output = zipSync({
      'document.md': new TextEncoder().encode(`
        PAYSLIP FOR MAY-2023
        EARNINGS
        BASIC 66703
        TOTAL EARNINGS 109412
        DEDUCTIONS
        CPF PC 11022
        TOTAL DEDUCTIONS 50969
        NET PAY 58443
      `),
    });
    const fetchImpl: typeof fetch = async (input, init) => {
      const url = String(input);
      calls.push({ url, init });
      if (url.endsWith('/doc-digitization/job/v1')) {
        return jsonResponse({ job_id: 'job-123', job_state: 'Accepted' }, 202);
      }
      if (url.endsWith('/upload-files')) {
        return jsonResponse({
          upload_urls: {
            'document-images.zip': {
              file_url: 'https://upload.example/document-images.zip',
              headers: { 'x-upload-token': 'token' },
            },
          },
        });
      }
      if (url === 'https://upload.example/document-images.zip') {
        return new Response(null, { status: 200 });
      }
      if (url.endsWith('/job-123/start')) {
        return jsonResponse({ job_id: 'job-123', job_state: 'Accepted' }, 202);
      }
      if (url.endsWith('/job-123/status')) {
        return jsonResponse({ job_id: 'job-123', job_state: 'Completed' });
      }
      if (url.endsWith('/job-123/download-files')) {
        return jsonResponse({
          download_urls: {
            'document-output.zip': {
              file_url: 'https://download.example/document-output.zip',
            },
          },
        });
      }
      if (url === 'https://download.example/document-output.zip') {
        return new Response(Buffer.from(output), { status: 200 });
      }
      throw new Error(`Unexpected URL: ${url}`);
    };

    try {
      const result = await digitizeWithSarvam({
        bytes: Buffer.from('synthetic image'),
        mimeType: 'image/jpeg',
        fetchImpl,
      });

      assert.ok(result);
      assert.equal(result.jobId, 'job-123');
      assert.match(result.text, /NET PAY 58443/);

      const initialise = calls[0];
      assert.equal(initialise.url, 'https://api.sarvam.ai/doc-digitization/job/v1');
      assert.equal(
        (initialise.init?.headers as Record<string, string>)['api-subscription-key'],
        'test-sarvam-key',
      );
      assert.deepEqual(JSON.parse(String(initialise.init?.body)), {
        job_parameters: {
          language: 'hi-IN',
          output_format: 'md',
        },
      });

      const upload = calls.find((call) =>
        call.url === 'https://upload.example/document-images.zip');
      assert.ok(upload);
      const uploadBody = upload.init?.body as Buffer;
      assert.equal(uploadBody[0], 0x50);
      assert.equal(uploadBody[1], 0x4b);
      assert.equal(
        (upload.init?.headers as Record<string, string>)['x-upload-token'],
        'token',
      );
    } finally {
      if (previousKey) process.env.SARVAM_API_KEY = previousKey;
      else delete process.env.SARVAM_API_KEY;
    }
  });

  it('returns null on provider errors so the parser can fall back', async () => {
    const previousKey = process.env.SARVAM_API_KEY;
    process.env.SARVAM_API_KEY = 'test-sarvam-key';
    try {
      const result = await digitizeWithSarvam({
        bytes: Buffer.from('synthetic image'),
        mimeType: 'image/png',
        fetchImpl: async () =>
          jsonResponse({ error: { code: 'rate_limit_exceeded_error' } }, 429),
      });
      assert.equal(result, null);
    } finally {
      if (previousKey) process.env.SARVAM_API_KEY = previousKey;
      else delete process.env.SARVAM_API_KEY;
    }
  });

  it('does not call Sarvam when the key is absent', async () => {
    const previousKey = process.env.SARVAM_API_KEY;
    delete process.env.SARVAM_API_KEY;
    let called = false;
    try {
      const result = await digitizeWithSarvam({
        bytes: Buffer.from('synthetic image'),
        mimeType: 'image/png',
        fetchImpl: async () => {
          called = true;
          throw new Error('should not run');
        },
      });
      assert.equal(result, null);
      assert.equal(called, false);
    } finally {
      if (previousKey) process.env.SARVAM_API_KEY = previousKey;
    }
  });
});

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
