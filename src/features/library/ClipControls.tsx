import { useLiveQuery } from 'dexie-react-hooks';
import { Trash2, Upload, Video } from 'lucide-react';
import { useRef, useState } from 'react';
import { Button } from '@/components/ui';
import { db } from '@/data/db';
import { storeMedia } from '@/data/media';
import { CLIP_LOOP_SEC, CLIP_MAX_BYTES, CLIP_WARN_BYTES, probeVideo } from '@/lib/recorder';
import { formatBytes, requestPersistence } from '@/lib/storage';
import { useUI } from '@/store/ui';

/** "My clip": record with the iPhone camera or pick a video; stored on-device (IndexedDB) and plays offline. */
export function ClipControls({ exerciseId, name }: { exerciseId: string; name: string }) {
  const toast = useUI((s) => s.toast);
  const clip = useLiveQuery(() => db.clips.get(exerciseId), [exerciseId]);
  const media = useLiveQuery(() => (clip ? db.media.get(clip.blobId) : undefined), [clip?.blobId]);
  const camRef = useRef<HTMLInputElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);

  const save = async (file: File) => {
    if (file.size > CLIP_MAX_BYTES) return toast(`That video is ${formatBytes(file.size)}. Please keep clips under 150 MB.`);
    setBusy(true);
    try {
      const { durationSec, thumb } = await probeVideo(file);
      const old = await db.clips.get(exerciseId);
      const blobId = await storeMedia(file, 'clip', 'video/quicktime');
      await db.transaction('rw', db.media, db.clips, async () => {
        await db.clips.put({ exerciseId, blobId, durationSec, thumb });
        if (old) await db.media.delete(old.blobId);
      });
      await requestPersistence();
      const notes = [durationSec > CLIP_LOOP_SEC ? `It loops the first ${CLIP_LOOP_SEC}s` : '', file.size > CLIP_WARN_BYTES ? `large file (${formatBytes(file.size)})` : ''].filter(Boolean).join(' · ');
      toast(`Clip saved for ${name}${notes ? `. ${notes}` : ''}`, { tone: 'success' });
    } catch (e) {
      console.error(e);
      toast('Could not save that clip. Is storage full?');
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!clip) return;
    const m = await db.media.get(clip.blobId);
    await db.transaction('rw', db.media, db.clips, async () => {
      await db.clips.delete(exerciseId);
      await db.media.delete(clip.blobId);
    });
    toast('Clip deleted', {
      undo: async () => {
        if (m) await db.media.put(m);
        await db.clips.put(clip);
      },
    });
  };

  return (
    <div className="flex gap-2">
      <Button variant="secondary" className="flex-1" onClick={() => camRef.current?.click()} disabled={busy}>
        <Video size={18} aria-hidden /> {clip ? 'Replace clip' : 'Record my clip'}
      </Button>
      <Button variant="secondary" onClick={() => fileRef.current?.click()} disabled={busy} aria-label="Upload a clip from your library">
        <Upload size={18} aria-hidden />
      </Button>
      {clip && (
        <Button variant="danger" onClick={remove} aria-label="Delete my clip">
          <Trash2 size={18} aria-hidden />
        </Button>
      )}
      <input ref={camRef} type="file" accept="video/*" capture="environment" className="hidden" aria-label={`Record a clip for ${name}`} onChange={(e) => e.target.files?.[0] && save(e.target.files[0]).finally(() => (e.target.value = ''))} />
      <input ref={fileRef} type="file" accept="video/*" className="hidden" aria-label={`Upload a clip for ${name}`} onChange={(e) => e.target.files?.[0] && save(e.target.files[0]).finally(() => (e.target.value = ''))} />
      {media && <span className="sr-only">Clip size {formatBytes(media.bytes)}</span>}
    </div>
  );
}
