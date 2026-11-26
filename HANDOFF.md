**Live URL: https://repmate-test.vercel.app**

# Repmate: handoff

Built end to end (M0 → M8 plus the extras you asked for during the build), deployed to Vercel project **repmate-test** (Hobby / personal scope). Source: https://github.com/dev-rakeshpurohit/personal-trainer

## Access code
The app is invite-only. The code is **not** in this repo: it's in the final chat message and in the git-ignored `.access-code.local` on your Mac. Share it only with people you want to use Repmate. To change it: `pnpm gen:code` then redeploy (people already set up stay unlocked).
With no server, the gate keeps casual visitors out but isn't strong security. Nobody's data is exposed either way, because it never leaves their phone.

## Install on your iPhone 13
1. Safari → open the live URL (with signal) → enter the code.
2. Choose **Build my plan** (or the Lean & Athletic template) → finish the steps.
3. **Share → Add to Home Screen** → open from the icon. From now on it works in airplane mode.
4. In the workout menu, tap **Enable rest-over notifications** (needs the Home Screen app, iOS 16.4+).
Android: Chrome → Install app.

> If you already opened the first-look version: your profile is kept and you won't be asked for the code. Use **More → My plan setup** to set your goal and equipment, then **Apply changes** (or **Start fresh**, which keeps history).

## Test on your phone (real-device checklist)
1. Fresh install → code → onboarding → plan created.
2. Airplane mode → open the app → start today's session → log 3 sets → lock the screen during rest → the timer is correct on unlock.
3. Kill the app mid-session → reopen → resume bar → same exercise and set.
4. Swap an exercise (Busy? / Alternates) → its history is kept separately (Library → exercise).
5. Record a clip offline (Library → exercise → Record my clip) → restart → it plays.
6. Log meals → totals are right; on a rest day the pre-gym snack is hidden.
7. Export (More → Backup) → Save to Files → Settings → Erase all → enter code → Restore → everything is back.
8. Deploy an update → the "New version" prompt appears, but not during an active workout.
9. Wake lock: during a workout the screen shouldn't dim (🔒 icon in the player header).

## What was built
- [x] **M0** Scaffold: Vite/React/TS strict, Tailwind, PWA (injectManifest SW), icons + iPhone 13 splash, vercel.json headers
- [x] **M1** Dexie schema, zod-validated seed import, 190 offline demo images, onboarding, `storage.persist()`
- [x] **M2** Today, Train week view, Library + exercise detail
- [x] **M3** Workout player: supersets, rest/work timers, chime + flash + notification, wake lock, swaps, PRs, summary
- [x] **M4** My clip: record/upload, on-device storage, offline playback
- [x] **M5** Eat: meals, swaps/skips with undo, rotation, rest-day menu, totals, habits
- [x] **M6** Progress (charts, projection, diet coach), photos, history calendar + edit/delete
- [x] **M7** Plan + diet editors (drag to reorder), settings, storage, backup/restore, templates
- [x] **M8** QA: 276 unit tests, 34 Playwright specs on iPhone 13 WebKit (incl. a full session with no network, resume, backup round-trip), Lighthouse mobile: Performance 96 · Accessibility 100 · Best practices 100

**Added at your request during the build**
- Missed-session **auto re-plan** (with "Keep original plan").
- Researched **alternates** (276 across 49 exercises), an **8-week intensity wave**, **Express** sessions and a busy-week fallback (docs/09-RESEARCH.md).
- **Gradual HIIT ramp** (beginner start).
- **Post-session feedback** that tunes the next session.
- **Anyone can use it:** goal-based **plan + diet generators**, **gym equipment** (unavailable exercises are never planned), **My plan setup** (apply changes anytime or start fresh), and the **invite code**.

## Known limitations
- **Notifications:** iOS can suspend the service worker, so the "rest over" notification may arrive late or only when you reopen the app. The on-screen timer is always correct.
- **Reminders:** pre-gym and water reminders aren't scheduled (no reliable background scheduling for PWAs without a server). Today shows what's next instead.
- **Storage:** iOS may evict data from apps you don't use for weeks. Storage persistence is requested; keep the monthly backup (Today reminds you).
- **Real-device checks:** wake lock, camera capture and HEVC playback were verified only in WebKit automation, not on a physical iPhone. Please run the checklist above.
- **Offline tests:** Playwright's WebKit `setOffline` can't exercise service workers, so the offline specs kill the server instead (a real network failure). See DECISIONS.
- **Diet values:** typical food values. Good for planning, not medical nutrition.
- **Privacy:** `docs/01-PRD.md` contains your persona details (age, weight, goals). Make the GitHub repo private if you'd rather keep those out of public view; the app bundle itself contains no personal data.

## Decisions
Every judgement call is logged with date and reason in [docs/DECISIONS.md](docs/DECISIONS.md). Research and citations are in [docs/09-RESEARCH.md](docs/09-RESEARCH.md).

## Redeploy later
```bash
pnpm i && pnpm build                         # optional local check
pnpm dlx vercel@latest deploy --prod --yes   # production → https://repmate-test.vercel.app
```
The Vercel ↔ GitHub auto-connect didn't link during setup (the Vercel GitHub app probably doesn't have access to the repo). To deploy on every push, connect the repo in Vercel → Project → Settings → Git.

## Update 2026-11-26: 3D library, Plan check, AI coach

- **3D demos for every exercise:** 1,320 exercises with animated 3D demos (© Gym visual, personal use). The media is git-ignored, so run `pnpm fetch:demos` (≈2 min, 45 MB) before building or deploying from a fresh clone. `pnpm import:dataset` regenerates `seed/library.dataset.json`.
- **Offline demos:** Your plan's demos are cached automatically. More → Storage → "Download all demos" fetches the rest (≈40 MB).
- **Plan check (Train tab):** weekly sets per muscle group against your goal, with one-tap fixes for any gap. For your plan it flags calves (0 sets a week).
- **Other days are preview-only:** you can open any day's session to look at it, but only today's can be started.
- **AI coach** (More → AI coach, Train tab, or the end of onboarding): describe yourself or a change in plain words, preview the plan, then apply it. History is kept.
  - Server: `api/coach.ts` on Vercel, with `OPENROUTER_API_KEY` stored as an encrypted production env var. Optional `OPENROUTER_MODEL`, default `anthropic/claude-haiku-5.5`.
  - Cost: ≈US$0.004 for a diet and ≈US$0.009 for a full workout + diet. Takes 30–50 s.
  - Access: the invite code is required, and requests are rate-limited to 12 per hour per IP.
  - **Recommended:** set a monthly credit limit on that key in the OpenRouter dashboard, or create a dedicated key just for Repmate.
