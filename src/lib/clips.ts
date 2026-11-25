import { useLiveQuery } from 'dexie-react-hooks';
import { useEffect, useState } from 'react';
import { db } from '@/data/db';

/** Object URL for the user's clip of an exercise (revoked on unmount). */
export function useClipUrl(exerciseId: string | undefined): string | undefined {
  const blob = useLiveQuery(async () => {
    if (!exerciseId) return null;
    const c = await db.clips.get(exerciseId);
    if (!c) return null;
    return (await db.media.get(c.blobId))?.blob ?? null;
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

export const youtubeUrl = (q: string | undefined, name: string) =>
  `https://www.youtube.com/results?search_query=${encodeURIComponent(q ?? `${name} proper form`)}`;
