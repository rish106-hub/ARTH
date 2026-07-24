import { unzipSync, zipSync } from 'fflate';
import { z } from 'zod';

const jobSchema = z.object({
  job_id: z.string().min(1),
  job_state: z.string().optional(),
}).passthrough();

const statusSchema = z.object({
  job_id: z.string().min(1),
  job_state: z.string().min(1),
  error_message: z.string().nullish(),
}).passthrough();

const uploadLinksSchema = z.object({
  upload_urls: z.record(z.string(), z.unknown()),
}).passthrough();

const downloadLinksSchema = z.object({
  download_urls: z.record(z.string(), z.unknown()),
}).passthrough();

type Fetch = typeof globalThis.fetch;

export type SarvamDigitizationResult = {
  text: string;
  jobId: string;
  language: string;
  outputFormat: 'md';
};

export async function digitizeWithSarvam(input: {
  bytes: Buffer;
  mimeType: string;
  fetchImpl?: Fetch;
}): Promise<SarvamDigitizationResult | null> {
  const apiKey = process.env.SARVAM_API_KEY?.trim();
  if (!apiKey) return null;

  const fetchImpl = input.fetchImpl ?? globalThis.fetch;
  const baseUrl = (process.env.SARVAM_API_BASE_URL || 'https://api.sarvam.ai')
    .replace(/\/+$/, '');
  const language = process.env.SARVAM_DOCUMENT_LANGUAGE || 'hi-IN';
  const timeoutMs = boundedNumber(
    process.env.SARVAM_TIMEOUT_MS,
    25_000,
    5_000,
    45_000,
  );
  const deadline = Date.now() + timeoutMs;
  const headers = {
    'api-subscription-key': apiKey,
    'content-type': 'application/json',
  };

  try {
    const job = jobSchema.parse(await requestJson(fetchImpl, {
      url: `${baseUrl}/doc-digitization/job/v1`,
      method: 'POST',
      headers,
      body: {
        job_parameters: {
          language,
          output_format: 'md',
        },
      },
      deadline,
    }));

    const upload = prepareUpload(input.bytes, input.mimeType);
    const links = uploadLinksSchema.parse(await requestJson(fetchImpl, {
      url: `${baseUrl}/doc-digitization/job/v1/upload-files`,
      method: 'POST',
      headers,
      body: {
        job_id: job.job_id,
        files: [upload.filename],
      },
      deadline,
    }));
    const uploadTarget = linkForFile(links.upload_urls, upload.filename);
    await uploadBytes(fetchImpl, uploadTarget, upload.bytes, deadline);

    await requestJson(fetchImpl, {
      url: `${baseUrl}/doc-digitization/job/v1/${encodeURIComponent(job.job_id)}/start`,
      method: 'POST',
      headers,
      body: {},
      deadline,
    });

    await waitForCompletion(fetchImpl, {
      baseUrl,
      jobId: job.job_id,
      headers,
      deadline,
    });

    const downloads = downloadLinksSchema.parse(await requestJson(fetchImpl, {
      url: `${baseUrl}/doc-digitization/job/v1/${encodeURIComponent(job.job_id)}/download-files`,
      method: 'POST',
      headers,
      body: {},
      deadline,
    }));
    const text = await downloadText(
      fetchImpl,
      downloads.download_urls,
      upload.filename,
      deadline,
    );
    if (text.replace(/\s/g, '').length < 40) return null;

    return {
      text: text.slice(0, 100_000),
      jobId: job.job_id,
      language,
      outputFormat: 'md',
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'unknown_error';
    console.warn(`[Sarvam] document digitization failed: ${reason.slice(0, 500)}`);
    return null;
  }
}

function prepareUpload(bytes: Buffer, mimeType: string) {
  if (mimeType === 'application/pdf') {
    return {
      filename: 'document.pdf',
      bytes: new Uint8Array(bytes),
    };
  }
  if (mimeType === 'image/jpeg' || mimeType === 'image/png') {
    const extension = mimeType === 'image/png' ? 'png' : 'jpg';
    const imageName = `document.${extension}`;
    return {
      filename: 'document-images.zip',
      bytes: zipSync({ [imageName]: new Uint8Array(bytes) }, { level: 6 }),
    };
  }
  throw new Error(`unsupported_mime_type:${mimeType}`);
}

async function waitForCompletion(
  fetchImpl: Fetch,
  input: {
    baseUrl: string;
    jobId: string;
    headers: Record<string, string>;
    deadline: number;
  },
) {
  let delayMs = 500;
  while (Date.now() < input.deadline) {
    const status = statusSchema.parse(await requestJson(fetchImpl, {
      url: `${input.baseUrl}/doc-digitization/job/v1/${encodeURIComponent(input.jobId)}/status`,
      method: 'GET',
      headers: input.headers,
      deadline: input.deadline,
    }));
    if (status.job_state === 'Completed' || status.job_state === 'PartiallyCompleted') {
      return;
    }
    if (status.job_state === 'Failed') {
      throw new Error(`job_failed:${status.error_message || 'unknown'}`);
    }
    await sleep(Math.min(delayMs, Math.max(input.deadline - Date.now(), 0)));
    delayMs = Math.min(Math.round(delayMs * 1.5), 1_500);
  }
  throw new Error('job_timeout');
}

async function downloadText(
  fetchImpl: Fetch,
  links: Record<string, unknown>,
  uploadedFilename: string,
  deadline: number,
) {
  const candidates = Object.entries(links)
    .filter(([filename]) => filename !== uploadedFilename)
    .sort(([left], [right]) => outputPriority(left) - outputPriority(right));
  for (const [filename, rawTarget] of candidates) {
    const target = parseLink(rawTarget);
    const response = await fetchWithDeadline(fetchImpl, target.url, {
      method: 'GET',
      headers: target.headers,
    }, deadline);
    if (!response.ok) continue;
    const bytes = new Uint8Array(await response.arrayBuffer());
    const text = textFromOutput(filename, bytes);
    if (text) return text;
  }
  throw new Error('output_text_not_found');
}

function textFromOutput(filename: string, bytes: Uint8Array): string | null {
  if (filename.toLowerCase().endsWith('.zip')) {
    const files = unzipSync(bytes);
    const preferred = Object.entries(files)
      .sort(([left], [right]) => outputPriority(left) - outputPriority(right));
    for (const [name, content] of preferred) {
      const text = textFromOutput(name, content);
      if (text) return text;
    }
    return null;
  }
  const decoded = new TextDecoder().decode(bytes).trim();
  if (filename.toLowerCase().endsWith('.md')
    || filename.toLowerCase().endsWith('.html')
    || filename.toLowerCase().endsWith('.txt')) {
    return decoded;
  }
  if (filename.toLowerCase().endsWith('.json')) {
    try {
      return collectJsonText(JSON.parse(decoded));
    } catch {
      return null;
    }
  }
  return null;
}

function collectJsonText(value: unknown): string {
  const parts: string[] = [];
  const visit = (current: unknown, key = '') => {
    if (typeof current === 'string') {
      if (/content|text|markdown|html/i.test(key) && current.trim()) {
        parts.push(current.trim());
      }
      return;
    }
    if (Array.isArray(current)) {
      current.forEach((item) => visit(item, key));
      return;
    }
    if (current && typeof current === 'object') {
      Object.entries(current).forEach(([childKey, child]) => visit(child, childKey));
    }
  };
  visit(value);
  return parts.join('\n\n');
}

async function requestJson(
  fetchImpl: Fetch,
  input: {
    url: string;
    method: string;
    headers: Record<string, string>;
    body?: unknown;
    deadline: number;
  },
) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const response = await fetchWithDeadline(fetchImpl, input.url, {
      method: input.method,
      headers: input.headers,
      body: input.body === undefined ? undefined : JSON.stringify(input.body),
    }, input.deadline);
    if (response.ok) return response.json();
    const body = (await response.text()).slice(0, 500);
    if (!isTransient(response.status) || attempt === 2) {
      throw new Error(`http_${response.status}:${body}`);
    }
    await sleep(Math.min(300 * (2 ** attempt), Math.max(input.deadline - Date.now(), 0)));
  }
  throw new Error('request_retry_exhausted');
}

async function uploadBytes(
  fetchImpl: Fetch,
  target: { url: string; headers: Record<string, string> },
  bytes: Uint8Array,
  deadline: number,
) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const response = await fetchWithDeadline(fetchImpl, target.url, {
      method: 'PUT',
      headers: target.headers,
      body: Buffer.from(bytes),
    }, deadline);
    if (response.ok) return;
    if (!isTransient(response.status) || attempt === 2) {
      throw new Error(`upload_http_${response.status}`);
    }
    await sleep(Math.min(300 * (2 ** attempt), Math.max(deadline - Date.now(), 0)));
  }
  throw new Error('upload_retry_exhausted');
}

function linkForFile(links: Record<string, unknown>, filename: string) {
  const exact = links[filename];
  if (exact) return parseLink(exact);
  const first = Object.values(links)[0];
  if (!first) throw new Error('upload_url_not_found');
  return parseLink(first);
}

function parseLink(value: unknown): { url: string; headers: Record<string, string> } {
  if (typeof value === 'string') return { url: value, headers: {} };
  if (!value || typeof value !== 'object') throw new Error('invalid_presigned_url');
  const fields = value as Record<string, unknown>;
  const url = [fields.file_url, fields.upload_url, fields.url]
    .find((candidate) => typeof candidate === 'string');
  if (typeof url !== 'string') throw new Error('invalid_presigned_url');
  const rawHeaders = fields.headers;
  const headers = rawHeaders && typeof rawHeaders === 'object'
    ? Object.fromEntries(
        Object.entries(rawHeaders as Record<string, unknown>)
          .filter((entry): entry is [string, string] => typeof entry[1] === 'string'),
      )
    : {};
  return { url, headers };
}

async function fetchWithDeadline(
  fetchImpl: Fetch,
  url: string,
  init: RequestInit,
  deadline: number,
) {
  const remaining = deadline - Date.now();
  if (remaining <= 0) throw new Error('job_timeout');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), remaining);
  try {
    return await fetchImpl(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

function outputPriority(filename: string) {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.md')) return 0;
  if (lower.endsWith('.json')) return 1;
  if (lower.endsWith('.html')) return 2;
  if (lower.endsWith('.txt')) return 3;
  if (lower.endsWith('.zip')) return 4;
  return 10;
}

function isTransient(status: number) {
  return status === 408 || status === 429 || status >= 500;
}

function boundedNumber(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
) {
  const value = Number.parseInt(raw || '', 10);
  return Number.isFinite(value) ? Math.min(Math.max(value, min), max) : fallback;
}

function sleep(ms: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}
