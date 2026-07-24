import { randomUUID } from 'node:crypto';
import { GoogleAuth } from 'google-auth-library';
import { env } from './config.js';

export type StoredObject = {
  objectName: string;
  generation: string;
  size: number;
};

export interface DocumentObjectStore {
  putCiphertext(ciphertext: Buffer): Promise<StoredObject>;
  deleteObject(objectName: string, generation: string): Promise<void>;
}

export class GcsDocumentObjectStore implements DocumentObjectStore {
  private readonly auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/devstorage.read_write'],
  });

  constructor(private readonly bucket = env.GCS_DOCUMENT_BUCKET) {
    if (!bucket) throw new Error('GCS_DOCUMENT_BUCKET is not configured');
  }

  async putCiphertext(ciphertext: Buffer): Promise<StoredObject> {
    const objectName = `objects/${randomUUID()}`;
    const client = await this.auth.getClient();
    const response = await client.request<{
      name?: string;
      generation?: string;
      size?: string;
    }>({
      method: 'POST',
      url: `https://storage.googleapis.com/upload/storage/v1/b/${encodeURIComponent(this.bucket!)}/o`,
      params: {
        uploadType: 'media',
        name: objectName,
        ifGenerationMatch: '0',
      },
      headers: {
        'Content-Type': 'application/octet-stream',
        'Cache-Control': 'no-store',
      },
      body: new Uint8Array(ciphertext),
    });
    if (!response.data.name || !response.data.generation) {
      throw new Error('GCS upload returned incomplete object metadata');
    }
    return {
      objectName: response.data.name,
      generation: response.data.generation,
      size: Number(response.data.size ?? ciphertext.length),
    };
  }

  async deleteObject(objectName: string, generation: string): Promise<void> {
    const client = await this.auth.getClient();
    await client.request({
      method: 'DELETE',
      url: `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(this.bucket!)}/o/${encodeURIComponent(objectName)}`,
      params: { ifGenerationMatch: generation },
    });
  }
}
