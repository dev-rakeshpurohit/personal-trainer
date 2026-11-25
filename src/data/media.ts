import { db, uid } from './db';
import type { MediaBlob } from '@/domain/types';

export async function fileToBuffer(file: Blob): Promise<ArrayBuffer> {
  if (typeof file.arrayBuffer === 'function') return file.arrayBuffer();
  return new Promise((res, rej) => {
    const r = new FileReader();
    r.onload = () => res(r.result as ArrayBuffer);
    r.onerror = () => rej(r.error);
    r.readAsArrayBuffer(file);
  });
}

export const mediaToBlob = (m: Pick<MediaBlob, 'data' | 'mime'>): Blob => new Blob([m.data], { type: m.mime });

export async function storeMedia(file: Blob, kind: MediaBlob['kind'], fallbackMime: string): Promise<string> {
  const id = uid();
  const data = await fileToBuffer(file);
  await db.media.add({ id, kind, mime: file.type || fallbackMime, bytes: data.byteLength, data, createdAt: new Date().toISOString() });
  return id;
}
