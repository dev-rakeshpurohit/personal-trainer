import { useLiveQuery } from 'dexie-react-hooks';
import { ShieldCheck, ShieldAlert } from 'lucide-react';
import { useEffect, useState } from 'react';
import { BackButton } from '@/components/BackButton';
import { Button, Card, PageHeader } from '@/components/ui';
import { db } from '@/data/db';
import { formatBytes, requestPersistence, storageEstimate } from '@/lib/storage';

export default function Storage() {
  const [est, setEst] = useState<{ usage: number; quota: number; persisted: boolean }>();
  const media = useLiveQuery(async () => {
    const all = await db.media.toArray();
    return { clips: all.filter((m) => m.kind === 'clip'), photos: all.filter((m) => m.kind === 'photo') };
  }, []);
  const refresh = () => void storageEstimate().then(setEst);
  useEffect(refresh, []);
  const sum = (l?: { bytes: number }[]) => (l ?? []).reduce((a, m) => a + m.bytes, 0);
  return (
    <div className="pb-6">
      <PageHeader title="Storage" right={<BackButton to="/more" />} />
      <div className="space-y-3 px-4">
        <Card>
          <p className="flex items-center gap-2 font-semibold">
            {est?.persisted ? <ShieldCheck size={20} className="text-success" aria-hidden /> : <ShieldAlert size={20} className="text-warning" aria-hidden />}
            {est?.persisted ? 'Storage is protected' : 'Storage may be cleared by iOS'}
          </p>
          <p className="mt-1 text-[15px] text-muted">{est?.persisted ? 'The browser promised not to evict your data.' : 'Use the app regularly and keep monthly backups.'}</p>
          {!est?.persisted && (
            <Button variant="secondary" className="mt-3" onClick={() => requestPersistence().then(refresh)}>
              Ask to keep data
            </Button>
          )}
        </Card>
        <Card>
          <dl className="space-y-2 text-[15px]">
            <div className="flex justify-between"><dt className="text-muted">My clips ({media?.clips.length ?? 0})</dt><dd className="font-semibold tnum">{formatBytes(sum(media?.clips))}</dd></div>
            <div className="flex justify-between"><dt className="text-muted">Photos ({media?.photos.length ?? 0})</dt><dd className="font-semibold tnum">{formatBytes(sum(media?.photos))}</dd></div>
            <div className="flex justify-between"><dt className="text-muted">Total used by Repmate</dt><dd className="font-semibold tnum">{est ? formatBytes(est.usage) : '–'}</dd></div>
            {est?.quota ? <div className="flex justify-between"><dt className="text-muted">Available</dt><dd className="font-semibold tnum">{formatBytes(est.quota)}</dd></div> : null}
          </dl>
        </Card>
      </div>
    </div>
  );
}
