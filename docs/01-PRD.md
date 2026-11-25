# 01 — Product Requirements: Repmate

## 1. Vision
The gym coach and food diary in your pocket that **just works in the gym**: no signal needed, no ads, no account, no clutter. Open it, see today's plan, tap through your sets, and the app does the remembering, timing, progressing and nudging.

**One-line promise:** *"Open → today's plan → tap, tap, done. It remembers everything and tells you when to go heavier."*

## 2. Primary user (persona)
**Rakesh, 37, Mumbai.** Tech director with a busy schedule. Trains Tue–Sat 9:15–10:30 AM; the gym is closed Monday. Started 2 months ago with a personal trainer. Goal: fat loss plus lean, athletic muscle (79 → 73 kg, 5'10"). Diet: vegetarian + eggs, low lactose, no paneer, about 2,000 kcal / 150 g protein, cooked by a home cook. Uses creatine and whey isolate. The gym is crowded at peak hour, so he often needs a swap exercise. Patchy signal inside the gym.

**Secondary users:** anyone following a structured gym + diet plan who wants the same thing: friends and family, or anyone the app gets shared with. They onboard with their own profile and can start from a template or build their own plan.

## 3. Goals and non-goals
**Goals**
- G1: Log a full session in under 60 seconds of total screen interaction.
- G2: Work 100% offline after first install.
- G3: Show clearly whether the plan is working (weekly-average weight, waist, strength trend).
- G4: Auto-coach: suggest the next weight, flag the deload week, suggest diet adjustments from the rules.
- G5: Be pleasant enough to open daily: fast, beautiful, calm.

**Non-goals (v1):** social feed, cloud accounts, AI chat, barcode food scanning, calorie database search, wearable sync (PWAs can't read Apple Health or Google Fit).

## 4. Features and priority
P0 = must ship in v1 (MVP). P1 = v1.1. P2 = later.

### P0 — MVP
| # | Feature | Summary |
|---|---|---|
| F1 | Onboarding | Name, sex, age, height, weight, goal weight, target date, training days, session time, diet type. Option to import the "Lean & Athletic" template + "Veg + eggs 2,000 kcal" diet from `/seed`. Takes under 90 seconds. |
| F2 | Today screen | The home screen. Today's workout card (or rest / active-recovery card), the next meal, a habit ring (steps, water, creatine, oil, sleep), today's protein/kcal progress, and a "Start workout" button. |
| F3 | Workout player (gym mode) | One exercise per screen. Set rows prefilled with last time's weight and reps. Tick to log. Rest timer starts automatically. Supersets alternate A1→A2. One-tap **Swap** to the alternative. Demo media. Notes. Screen stays awake. |
| F4 | Rest timer | Big countdown, ±15 s, skip. Uses timestamps so it stays correct if the screen locks. Chime + vibration (where supported) + local notification at 0. |
| F5 | Exercise library | All exercises with offline demo (2-frame animation), cue text, primary muscles, the user's own recorded clip, and a YouTube link (only shown when online). |
| F6 | My clip (offline video) | Record or upload a clip of up to 20 s per exercise (e.g. the trainer demonstrating). Stored on the device, plays offline, loops. |
| F7 | Diet tracker | Today's meals from the diet plan as tickable cards (eaten / swapped / skipped), rotating snack options, live protein and kcal totals vs target. Rest-day variant applied automatically. |
| F8 | Habits | Steps (manual entry), water (+250 ml taps), creatine tick, oil-limit tick, sleep hours. |
| F9 | Body log | Weight (daily), waist (every 2 weeks), progress photos (on device only). Chart shows daily dots plus a 7-day average line plus the goal line. |
| F10 | Progress | Weekly-average trend, rate of loss (kg/week), estimated goal date, strength trend per lift (best estimated 1RM), PR list, sessions per week, streak. |
| F11 | History | Calendar of sessions. Tap a day to see the full log. Edit or delete any entry. |
| F12 | Plan editor | Edit days, exercises, sets, rep ranges, rest, swaps and order. Add exercises from the library or create custom ones. Edit diet meals and targets. |
| F13 | Auto-coach | "Go heavier next time" badges (double progression), deload-week banner (week 8), 2-week diet-adjustment card (rule table). See doc 06. |
| F14 | Backup | Export everything to one JSON file (videos optional, as a .zip). Import or restore. A monthly reminder to back up. |
| F15 | PWA | Installable, offline, app icon, splash, standalone display, update prompt ("New version — reload"). |
| F16 | Settings | Units (kg/lb), theme (dark/light/system), rest-timer sound and vibration, week start, reminder times, data management, about. |

### P1 — v1.1
- Local reminders: pre-gym (8:30), meals, water, a weigh-in nudge. Local notifications; iOS support depends on version (see doc 05).
- Gym-crowd mode: a single toggle that applies every swap for the session.
- Plate and dumbbell math: "Add 2 kg per hand → 14 kg".
- Session summary share card (image) with volume, PRs and duration.
- Grocery and prep list generated from the weekly diet (for the cook), in English and Hindi, shareable.
- Template marketplace (local JSON): PPL, upper/lower, beginner full-body, a women's strength template.
- Week planner: drag sessions between days (e.g. moving Saturday to Sunday) and the app reflows.

### P2 — later
- Optional encrypted cloud sync (Supabase) across devices.
- AI coach (online-only) that reads the local summary and suggests tweaks, with explicit consent.
- Apple Watch / Wear OS companion (would need native).
- Heart-rate strap via Web Bluetooth (Android Chrome only).

## 5. Key user stories and acceptance criteria
**US1 — Start today's workout in the gym with no signal.**
Given the app is installed and was opened at least once online, when I open it in airplane mode on Tuesday, then the Today screen shows "Strength A" and Start opens the player with every exercise, cue, image and my clips. *AC: Playwright offline spec passes; time from open to first set row is under 2 s on a mid-range Android.*

**US2 — Log a set in two taps.**
Weight and reps are prefilled from my last session. I adjust with steppers (±1 rep, ±0.5/1/2 kg per settings) and tap ✓. The set saves instantly and the rest timer starts. *AC: data is in IndexedDB before the animation ends; killing the app and reopening restores the in-progress session on the same set.*

**US3 — The bench is taken.**
I tap **Swap**. The exercise becomes "Dumbbell floor press" with its own demo and history, and the log records `swappedFrom`. *AC: progression history is tracked separately for the swap exercise.*

**US4 — Know when to add weight.**
When I hit the top of the rep range on all sets with the target RIR, the next session shows "↑ Try 16 kg" on that exercise. *AC: matches the rules in doc 06; unit-tested.*

**US5 — See if the diet is working.**
After 14 days of weigh-ins, Progress shows weekly-average loss, and if it's below 0.3 kg/week for 2 weeks it shows the adjustment card from the diet rules. *AC: handles missing days; needs at least 4 weigh-ins per week to compute.*

**US6 — Watch my trainer's form clip offline.**
I record a 15 s clip of my trainer doing the goblet squat. Later, offline, the exercise screen loops it muted. *AC: survives an app restart; the storage-persistence request has been made.*

**US7 — Never lose my data.**
Settings → Export creates `repmate-backup-YYYY-MM-DD.json`. Import on a new phone restores everything. *AC: round-trip test passes.*

## 6. Success metrics (personal)
- 5 sessions logged per week for 8 weeks.
- At least 4 weigh-ins per week.
- Weekly diet adherence of at least 80% of meals ticked.
- Rakesh opens the app daily without being prompted.

## 7. Constraints
- **Primary and only optimised target: iPhone 13 (iOS 17/18) as a Home Screen PWA.** Android/desktop just need to not break.
- Bundle under 300 KB gzipped JS for first load (excluding media). Media precache under 15 MB.
- No cookies, no tracking, no external fonts at runtime (self-host them).
