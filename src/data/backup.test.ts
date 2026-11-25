// @vitest-environment node
import { db } from './db';
import { buildBackup, exportBackup, markBackedUp, parseBackupFile, restoreBackup } from './backup';
import { importDietTemplate, importProgramTemplate } from './seed-import';

const snapshot = async () => {
  const out: Record<string, unknown[]> = {};
  for (const t of db.tables) {
    if (t.name === 'media') {
      out.media = (await t.toArray()).map((m: { id: string; bytes: number; data: ArrayBuffer }) => ({ id: m.id, bytes: m.bytes, data: [...new Uint8Array(m.data)] }));
    } else out[t.name] = (await t.toArray()).sort((a: { id?: string; key?: string; exerciseId?: string }, b: typeof a) =>
      String(a.id ?? a.key ?? a.exerciseId).localeCompare(String(b.id ?? b.key ?? b.exerciseId)));
  }
  return out;
};

beforeEach(async () => {
  await db.delete();
  await db.open();
  await importProgramTemplate();
  await importDietTemplate();
  await db.profile.put({
    id: 'me', name: 'Test', sex: 'male', birthYear: 1990, heightCm: 178, startWeightKg: 80, goalWeightKg: 74, units: 'kg', theme: 'dark',
    dietType: 'veg_egg', intolerances: [], kcalTarget: 2000, proteinTargetG: 150, trainingDays: ['TUE'], sessionTime: '09:15',
    restTimer: { sound: true, vibrate: true, notify: false }, stepKg: { dumbbell: 2, barbell: 5, machine: 5 }, weekStart: 'mon', createdAt: new Date().toISOString(),
  });
  await db.bodyLogs.add({ id: 'b1', dayKey: '2026-12-01', weightKg: 79.2 });
  await db.media.put({ id: 'm1', kind: 'clip', mime: 'video/mp4', bytes: 3, data: new Uint8Array([1, 2, 3]).buffer, createdAt: 'x' });
  await db.clips.put({ exerciseId: 'front-plank', blobId: 'm1', durationSec: 5 });
});

describe('backup', () => {
  it('JSON round-trip restores an identical DB (media omitted)', async () => {
    const { blob, filename, exportedAt } = await exportBackup(false, new Date(2026, 11, 1));
    await markBackedUp(exportedAt);
    const before = await snapshot();
    expect(filename).toBe('repmate-backup-2026-12-01.json');
    await db.delete();
    await db.open();
    await restoreBackup(await parseBackupFile(blob), 'replace');
    const after = await snapshot();
    expect({ ...after, media: undefined }).toEqual({ ...before, media: undefined });
  });
  it('zip round-trip includes media', async () => {
    const { blob, filename, exportedAt } = await exportBackup(true);
    await markBackedUp(exportedAt);
    const before = await snapshot();
    expect(filename.endsWith('.zip')).toBe(true);
    await db.delete();
    await db.open();
    await restoreBackup(await parseBackupFile(blob), 'replace');
    expect(await snapshot()).toEqual(before);
  });
  it('rejects garbage', async () => {
    await expect(parseBackupFile(new Blob(['{"hello":1}']))).rejects.toThrow(/not a Repmate backup/);
    await expect(parseBackupFile(new Blob(['nope']))).rejects.toThrow(/invalid JSON/);
  });
  it('merge keeps existing rows and adds new ones', async () => {
    const data = await buildBackup(false);
    await db.bodyLogs.add({ id: 'b2', dayKey: '2026-12-02', weightKg: 79 });
    await restoreBackup({ data, media: new Map() }, 'merge');
    expect(await db.bodyLogs.count()).toBe(2);
  });
});
