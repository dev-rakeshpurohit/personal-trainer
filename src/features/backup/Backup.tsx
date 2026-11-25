import { format, parseISO } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { Download, Upload } from 'lucide-react';
import { useRef, useState } from 'react';
import { BackButton } from '@/components/BackButton';
import { Toggle } from '@/components/Field';
import { Sheet } from '@/components/Sheet';
import { Button, Card, PageHeader } from '@/components/ui';
import { getMeta } from '@/data/db';
import { exportBackup, markBackedUp, parseBackupFile, restoreBackup, shareOrDownload, type ParsedBackup } from '@/data/backup';
import { useUI } from '@/store/ui';

export default function Backup() {
  const toast = useUI((s) => s.toast);
  const last = useLiveQuery(() => getMeta<string>('lastBackupAt'), []);
  const [media, setMedia] = useState(false);
  const [busy, setBusy] = useState(false);
  const [pending, setPending] = useState<ParsedBackup>();
  const fileRef = useRef<HTMLInputElement>(null);

  const doExport = async () => {
    setBusy(true);
    try {
      const { blob, filename, exportedAt } = await exportBackup(media);
      const r = await shareOrDownload(blob, filename);
      if (r !== 'cancelled') {
        await markBackedUp(exportedAt);
        toast(r === 'shared' ? 'Backup shared' : `Saved ${filename}`, { tone: 'success' });
      }
    } catch (e) {
      toast(`Export failed: ${(e as Error).message}`);
    } finally {
      setBusy(false);
    }
  };

  const pick = async (file: File) => {
    try {
      setPending(await parseBackupFile(file));
    } catch (e) {
      toast((e as Error).message);
    }
  };

  const restore = async (mode: 'replace' | 'merge') => {
    if (!pending) return;
    await restoreBackup(pending, mode);
    setPending(undefined);
    toast(mode === 'replace' ? 'Backup restored' : 'Backup merged', { tone: 'success' });
  };

  const counts = pending ? Object.entries(pending.data.tables).filter(([, v]) => v.length) : [];
  return (
    <div className="pb-6">
      <PageHeader title="Backup" right={<BackButton to="/more" />} />
      <div className="space-y-3 px-4">
        <Card>
          <p className="font-semibold">Export</p>
          <p className="mt-1 text-[15px] text-muted">
            Everything lives only on this phone. iOS can clear web-app data if it isn't used for a while, so save a backup to Files or iCloud once a month.
          </p>
          <p className="mt-2 text-[14px] text-muted">Last backup: {last ? format(parseISO(last), 'd MMM yyyy') : 'never'}</p>
          <Toggle checked={media} onChange={setMedia} label="Include clips & photos" sub="Creates a .zip (can be large)" />
          <Button block size="lg" onClick={doExport} disabled={busy}>
            <Download size={20} aria-hidden /> {busy ? 'Preparing…' : 'Export backup'}
          </Button>
        </Card>
        <Card>
          <p className="font-semibold">Restore</p>
          <p className="mt-1 text-[15px] text-muted">Import a .json or .zip backup from Repmate.</p>
          <Button variant="secondary" block size="lg" className="mt-3" onClick={() => fileRef.current?.click()}>
            <Upload size={20} aria-hidden /> Choose backup file
          </Button>
          <input
            ref={fileRef}
            type="file"
            accept=".json,.zip,application/json,application/zip"
            className="hidden"
            aria-label="Backup file to restore"
            onChange={(e) => {
              if (e.target.files?.[0]) void pick(e.target.files[0]);
              e.target.value = '';
            }}
          />
        </Card>
      </div>
      <Sheet open={!!pending} onClose={() => setPending(undefined)} title="Restore backup">
        {pending && (
          <div className="space-y-3 pb-3">
            <p className="text-[15px] text-muted">From {format(parseISO(pending.data.exportedAt), 'd MMM yyyy, HH:mm')}</p>
            <ul className="grid grid-cols-2 gap-1 text-[14px]">
              {counts.map(([k, v]) => (
                <li key={k} className="flex justify-between rounded-btn bg-surface2 px-3 py-1.5">
                  <span className="text-muted">{k}</span>
                  <span className="font-semibold tnum">{v.length}</span>
                </li>
              ))}
            </ul>
            <Button block size="lg" onClick={() => restore('replace')}>
              Replace everything
            </Button>
            <Button block variant="secondary" onClick={() => restore('merge')}>
              Merge with what's here
            </Button>
          </div>
        )}
      </Sheet>
    </div>
  );
}
