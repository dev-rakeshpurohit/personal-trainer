import { strFromU8, strToU8, unzipSync, zipSync } from 'fflate';
import { format } from 'date-fns';
import { db, DATA_TABLES, setMeta, type DataTable } from './db';
import { backupSchema, type Backup } from './schemas';
import type { MediaBlob } from '@/domain/types';

export const SCHEMA_VERSION = 1;

type Row = Record<string, unknown>;

export async function buildBackup(includeMedia: boolean): Promise<Backup> {
  const tables: Record<string, Row[]> = {};
  for (const t of DATA_TABLES) tables[t] = (await db.table(t).toArray()) as Row[];
  if (includeMedia) {
    const media = await db.media.toArray();
    tables.media = media.map(({ blob: _b, ...rest }) => rest);
  }
  return { app: 'repmate', schemaVersion: SCHEMA_VERSION, exportedAt: new Date().toISOString(), tables, media: includeMedia ? 'included-in-zip' : 'omitted' };
}

const ext = (mime: string) => (mime.includes('quicktime') ? 'mov' : mime.split('/')[1]?.split(';')[0] || 'bin');

export async function exportBackup(includeMedia: boolean, now = new Date()): Promise<{ blob: Blob; filename: string }> {
  const data = await buildBackup(includeMedia);
  const base = `repmate-backup-${format(now, 'yyyy-MM-dd')}`;
  const json = JSON.stringify(data);
  if (!includeMedia) return { blob: new Blob([json], { type: 'application/json' }), filename: `${base}.json` };
  const files: Record<string, Uint8Array> = { 'backup.json': strToU8(json) };
  for (const m of await db.media.toArray()) files[`media/${m.id}.${ext(m.mime)}`] = new Uint8Array(await blobToArrayBuffer(m.blob));
  const zipped = zipSync(files, { level: 0 });
  return { blob: new Blob([zipped], { type: 'application/zip' }), filename: `${base}.zip` };
}

function blobToArrayBuffer(b: Blob): Promise<ArrayBuffer> {
  if (typeof b.arrayBuffer === 'function') return b.arrayBuffer();
  return new Promise((res, rej) => {
    const r = new FileReader();
    r.onload = () => res(r.result as ArrayBuffer);
    r.onerror = () => rej(r.error);
    r.readAsArrayBuffer(b);
  });
}

export interface ParsedBackup {
  data: Backup;
  media: Map<string, Uint8Array>;
}

export async function parseBackupFile(file: Blob): Promise<ParsedBackup> {
  const buf = new Uint8Array(await blobToArrayBuffer(file));
  let json: string;
  const media = new Map<string, Uint8Array>();
  if (buf[0] === 0x50 && buf[1] === 0x4b) {
    const files = unzipSync(buf);
    if (!files['backup.json']) throw new Error('This zip has no backup.json');
    json = strFromU8(files['backup.json']);
    for (const [name, bytes] of Object.entries(files)) if (name.startsWith('media/')) media.set(name.slice(6).replace(/\.[^.]+$/, ''), bytes);
  } else {
    json = strFromU8(buf);
  }
  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch {
    throw new Error('That file is not a Repmate backup (invalid JSON).');
  }
  const parsed = backupSchema.safeParse(raw);
  if (!parsed.success) throw new Error('That file is not a Repmate backup.');
  if (parsed.data.schemaVersion > SCHEMA_VERSION) throw new Error('This backup is from a newer version of Repmate. Update the app first.');
  return { data: parsed.data, media };
}

export async function restoreBackup(p: ParsedBackup, mode: 'replace' | 'merge'): Promise<void> {
  const { data, media } = p;
  const all = [...DATA_TABLES.map((t) => db.table(t)), db.media];
  await db.transaction('rw', all, async () => {
    if (mode === 'replace') for (const t of all) await t.clear();
    for (const t of DATA_TABLES as readonly DataTable[]) {
      const rows = data.tables[t];
      if (rows?.length) await db.table(t).bulkPut(rows);
    }
    const metaRows = (data.tables.media ?? []) as unknown as Omit<MediaBlob, 'blob'>[];
    for (const m of metaRows) {
      const bytes = media.get(m.id);
      if (bytes) await db.media.put({ ...m, blob: new Blob([bytes], { type: m.mime }) });
    }
  });
}

export async function markBackedUp() {
  await setMeta('lastBackupAt', new Date().toISOString());
}

/** Share sheet on iOS (Save to Files / iCloud), download elsewhere. */
export async function shareOrDownload(blob: Blob, filename: string): Promise<'shared' | 'downloaded' | 'cancelled'> {
  const file = new File([blob], filename, { type: blob.type });
  const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
  if (nav.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: 'Repmate backup' });
      return 'shared';
    } catch (e) {
      if ((e as Error).name === 'AbortError') return 'cancelled';
    }
  }
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
  return 'downloaded';
}
