import { useLiveQuery } from 'dexie-react-hooks';
import { useEffect, useState } from 'react';
import { db } from '@/data/db';
import { mediaToBlob } from '@/data/media';
import demoMap from '../../seed/demo-map.json';

/** Object URL for the user's clip of an exercise (revoked on unmount). */
export function useClipUrl(exerciseId: string | undefined): string | undefined {
  const blob = useLiveQuery(async () => {
    if (!exerciseId) return null;
    const c = await db.clips.get(exerciseId);
    if (!c) return null;
    const m = await db.media.get(c.blobId);
    return m ? mediaToBlob(m) : null;
  }, [exerciseId]);
  const [url, setUrl] = useState<string>();
  useEffect(() => {
    if (!blob) {
      setUrl(undefined);
      return;
    }
    const u = URL.createObjectURL(blob);
    setUrl(u);
    return () => URL.revokeObjectURL(u);
  }, [blob]);
  return url;
}

export const demoSrc = (freeDbId: string | undefined, frame: 0 | 1) => (freeDbId ? `/media/exercises/${freeDbId}/${frame}.webp` : undefined);

/* Animated 3D demos (© Gym visual, personal use; see seed/demo-map.json + scripts/fetch-demos.ts). */
const DEMO_MAP = demoMap.map as Record<string, string | null>;
export const DEMO_CREDIT = '© Gym visual';
export const demoIdFor = (exerciseId: string | undefined): string | undefined => (exerciseId ? (DEMO_MAP[exerciseId] ?? undefined) : undefined);
export const demoAnimSrc = (exerciseId: string | undefined) => {
  const id = demoIdFor(exerciseId);
  return id ? `/media/demos/${id}.webp` : undefined;
};
/** Best still for lists: the 3D demo frame, else the free-exercise-db photo. */
export const exerciseThumb = (ex: { id: string; freeDbId?: string } | undefined): string | undefined => {
  const id = demoIdFor(ex?.id);
  return id ? `/media/demos/${id}-t.webp` : demoSrc(ex?.freeDbId, 0);
};

export const youtubeUrl = (q: string | undefined, name: string) =>
  `https://www.youtube.com/results?search_query=${encodeURIComponent(q ?? `${name} proper form`)}`;
