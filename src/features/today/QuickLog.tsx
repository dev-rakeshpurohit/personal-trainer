import { Camera } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Button, Chip } from '@/components/ui';
import { Sheet } from '@/components/Sheet';
import { Stepper } from '@/components/Stepper';
import { db, uid } from '@/data/db';
import { storeMedia } from '@/data/media';
import { getHabit, lastWaist, lastWeight, setHabit, upsertBody } from '@/data/repo';
import { fromUserUnits, toUserUnits } from '@/domain/units';
import type { Pose, Profile } from '@/domain/types';
import { useUI } from '@/store/ui';

export type QuickKind = 'weight' | 'waist' | 'photo' | 'steps';

export function QuickLogSheet({ kind, onClose, dayKey, profile }: { kind: QuickKind | null; onClose: () => void; dayKey: string; profile: Profile }) {
  const toast = useUI((s) => s.toast);
  const [v, setV] = useState<number>();
  const [pose, setPose] = useState<Pose>('front');
  const fileRef = useRef<HTMLInputElement>(null);
  const units = profile.units;

  useEffect(() => {
    setV(undefined);
    if (kind === 'weight') {
      void db.bodyLogs.where('dayKey').equals(dayKey).first().then(async (b) => {
        const w = b?.weightKg ?? (await lastWeight()) ?? profile.startWeightKg;
        setV(toUserUnits(w, units));
      });
    }
    if (kind === 'waist') void db.bodyLogs.where('dayKey').equals(dayKey).first().then(async (b) => setV(b?.waistCm ?? (await lastWaist()) ?? 85));
    if (kind === 'steps') void getHabit(dayKey, 'steps').then((s) => setV(s || 0));
  }, [kind, dayKey, profile.startWeightKg, units]);

  const save = async () => {
    if (v == null) return;
    if (kind === 'weight') {
      await upsertBody(dayKey, { weightKg: fromUserUnits(v, units) });
      toast(`Weight logged · ${v} ${units}`, { tone: 'success' });
    }
    if (kind === 'waist') {
      await upsertBody(dayKey, { waistCm: v });
      toast(`Waist logged · ${v} cm`, { tone: 'success' });
    }
    if (kind === 'steps') {
      await setHabit(dayKey, 'steps', v);
      toast(`Steps logged · ${v.toLocaleString()}`, { tone: 'success' });
    }
    onClose();
  };

  const savePhoto = async (file: File) => {
    const blobId = await storeMedia(file, 'photo', 'image/jpeg');
    await db.photos.add({ id: uid(), dayKey, pose, blobId });
    void navigator.storage?.persist?.();
    toast(`${pose[0].toUpperCase() + pose.slice(1)} photo saved on this phone`, { tone: 'success' });
    onClose();
  };

  const titles: Record<QuickKind, string> = { weight: 'Log weight', waist: 'Log waist', photo: 'Progress photo', steps: 'Steps today' };
  if (!kind) return null;
  return (
    <Sheet
      open={!!kind}
      onClose={onClose}
      title={titles[kind]}
      footer={
        kind === 'photo' ? (
          <Button block size="lg" onClick={() => fileRef.current?.click()}>
            <Camera size={20} aria-hidden /> Take {pose} photo
          </Button>
        ) : (
          <Button block size="lg" onClick={save} disabled={v == null}>
            Save
          </Button>
        )
      }
    >
      <div className="pb-2 pt-3">
        {kind === 'weight' && (
          <>
            <Stepper label="Body weight" value={v} onChange={setV} step={units === 'kg' ? 0.1 : 0.2} suffix={units} size="lg" decimals={1} />
            <p className="mt-3 text-center text-caption text-muted">Same time each morning, after the bathroom, before food. The 7-day average is what matters.</p>
          </>
        )}
        {kind === 'waist' && (
          <>
            <Stepper label="Waist" value={v} onChange={setV} step={0.5} suffix="cm" size="lg" decimals={1} />
            <p className="mt-3 text-center text-caption text-muted">At the navel, relaxed, every 2 weeks.</p>
          </>
        )}
        {kind === 'steps' && (
          <>
            <Stepper label="Steps" value={v} onChange={setV} step={500} suffix="steps" size="lg" decimals={0} inputMode="numeric" max={100000} />
            <div className="mt-3 flex flex-wrap justify-center gap-2">
              {[5000, 7000, 8000, 10000].map((n) => (
                <Chip key={n} active={v === n} onClick={() => setV(n)}>
                  {n.toLocaleString()}
                </Chip>
              ))}
            </div>
          </>
        )}
        {kind === 'photo' && (
          <>
            <div className="flex justify-center gap-2">
              {(['front', 'side', 'back'] as Pose[]).map((p) => (
                <Chip key={p} active={pose === p} onClick={() => setPose(p)}>
                  {p}
                </Chip>
              ))}
            </div>
            <p className="mt-3 text-center text-caption text-muted">Photos never leave this phone unless you export them.</p>
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              capture="user"
              className="hidden"
              aria-label="Progress photo"
              onChange={(e) => e.target.files?.[0] && savePhoto(e.target.files[0])}
            />
          </>
        )}
      </div>
    </Sheet>
  );
}
