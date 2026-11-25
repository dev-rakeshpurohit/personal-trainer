# 05 — Offline & Media (including "offline video")

## 1. The honest constraint about video
YouTube videos **cannot** be cached or played offline in a web app: it's against YouTube's Terms of Service, and their CORS/DRM setup blocks it anyway. So Repmate offers three layers of exercise demos:

| Layer | Works offline? | Source | Use |
|---|---|---|---|
| **1. Built-in demo** | ✅ Yes (precached) | [free-exercise-db](https://github.com/yuhonas/free-exercise-db), **public domain (Unlicense)**, 2 photos per exercise (start/end position) | Shown as a looping 2-frame animation (crossfade every 900 ms) = a mini "video". Default for every exercise. |
| **2. My clip** | ✅ Yes (stored on device) | The user records or uploads it (e.g. the trainer demonstrates, or the user films their own set for a form check) | Loops muted in the media panel. Preferred over layer 1 when present. |
| **3. YouTube** | ❌ Online only | A YouTube search URL built from `youtubeQuery` | A "▶ Watch on YouTube" chip, visible only when `navigator.onLine`. Opens externally. |

## 2. Built-in demo pipeline
- `seed/free-exercise-db-ids.json` lists the 42 ids the seed program uses.
- `scripts/fetch-media.ts` (run with `pnpm fetch:media`):
  1. For each id, download `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/<id>/0.jpg` and `/1.jpg`.
  2. Resize them to 480 px wide and convert to WebP (quality 72) with `sharp`.
  3. Write them to `public/media/exercises/<id>/0.webp`, `1.webp`.
  4. Write `public/media/exercises/index.json` (`{id, name, instructions[], primaryMuscles, equipment}`), taken from `dist/exercises.json` for those ids.
- Commit the generated files so the build is deterministic and works offline without the script.
- Custom exercises with no `freeDbId` show a clean placeholder card with the cue text, plus a "Record a clip" CTA.
- Credit it in About → Licences: "Exercise images from free-exercise-db (Unlicense)".
- Optional, later: "Download the full library" (873 exercises, about 60 MB) as a user-triggered runtime cache.

## 3. "My clip" (recording and storage)
- **Capture:** `<input type="file" accept="video/*" capture="environment">`. This is the most reliable option on iOS and Android. Offer `MediaRecorder` in-app recording on Android/desktop as an enhancement.
- **Limits:** 20 s max (trim the UI or reject longer files), and warn above 25 MB.
- **Compress (optional):** if the file is over 15 MB on a supporting browser, re-encode via a `<canvas>` + `MediaRecorder` at 720p. Otherwise store it as-is.
- **Store:** the Blob goes in the Dexie `media` table, with `clips[exerciseId] → blobId`. Play it via `URL.createObjectURL` and revoke on unmount.
- Use the `muted loop playsinline autoplay` attributes (needed for iOS autoplay).
- **Persistence:** call `navigator.storage.persist()` after the first clip. Show storage usage via `navigator.storage.estimate()` in Settings.
- Clips and photos are included in the backup only if the user chooses "Include media (.zip)" (use `fflate`).

## 4. Offline behaviour matrix
| Feature | Offline |
|---|---|
| Open app, every screen, log anything | ✅ |
| Rest timer + chime | ✅ |
| Rest timer notification while the screen is locked | ✅ Android. iOS 16.4+ only if installed to the Home Screen and permission is granted; otherwise it catches up when reopened |
| Built-in demos, my clips | ✅ |
| YouTube | ❌ (chip hidden) |
| Export backup | ✅ (download or share sheet) |
| App update | Downloads when back online. Prompted, never forced mid-session |

## 5. iOS PWA notes (test on a real iPhone)
- The user must tap **Share → Add to Home Screen**. Show a one-time install guide sheet on iOS Safari.
- Storage can be evicted if the app isn't used for weeks. Call `storage.persist()`, plus send a monthly backup reminder.
- `navigator.vibrate` isn't supported. Use sound plus a visual flash.
- Screen Wake Lock is supported in iOS 16.4+ standalone mode. Fall back to a silent looping video hack only if it's missing (document it in DECISIONS).
- Background JS is suspended, so always derive the timer from `restEndsAt`.

## 6. Connectivity UX
`useOnline()` hook. A small "Offline · everything works" pill on Today. No error toasts for being offline.
