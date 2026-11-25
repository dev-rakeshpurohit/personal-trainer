/** Read duration + a thumbnail frame from a video file (iPhone HEVC .mov plays in Safari, so no re-encode). */
export async function probeVideo(file: Blob): Promise<{ durationSec: number; thumb?: string }> {
  const url = URL.createObjectURL(file);
  try {
    const video = document.createElement('video');
    video.muted = true;
    video.playsInline = true;
    video.preload = 'metadata';
    video.src = url;
    const durationSec = await new Promise<number>((resolve) => {
      const done = () => resolve(Number.isFinite(video.duration) ? video.duration : 0);
      video.onloadedmetadata = done;
      video.onerror = () => resolve(0);
      setTimeout(() => resolve(0), 4000);
    });
    let thumb: string | undefined;
    try {
      video.currentTime = Math.min(0.5, durationSec / 2 || 0);
      await new Promise<void>((resolve) => {
        video.onseeked = () => resolve();
        setTimeout(resolve, 1500);
      });
      const w = 240;
      const h = video.videoWidth ? Math.round((w * video.videoHeight) / video.videoWidth) : 135;
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (ctx && video.videoWidth) {
        ctx.drawImage(video, 0, 0, w, h);
        thumb = canvas.toDataURL('image/jpeg', 0.7);
      }
    } catch {
      /* thumbnail is optional */
    }
    return { durationSec, thumb };
  } finally {
    URL.revokeObjectURL(url);
  }
}

export const CLIP_LOOP_SEC = 20;
export const CLIP_WARN_BYTES = 25 * 1024 * 1024;
export const CLIP_MAX_BYTES = 150 * 1024 * 1024;
