# 02 — UX / UI Spec

## 0. Target
Designed for **iPhone 13: 390×844 pt, notch, home indicator, one-handed use**. Respect the safe areas on every fixed bar. The thumb zone is the bottom 45%. No hover states.

## 1. Design principles
1. **Glanceable:** you should understand any screen in about 1 second at arm's length.
2. **Thumb-first:** primary actions sit in the bottom 40% of the screen; nothing important at the top corners.
3. **Zero typing in the gym:** steppers, chips and presets. The keyboard is only a fallback.
4. **Calm, not gamified-loud:** subtle celebration on PRs and streaks, no confetti spam.
5. **Forgiving:** every action can be undone (snackbar "Undo" for 5 s), and every entry can be edited later.

## 2. Information architecture
Bottom tab bar (5 tabs):
`Today` • `Train` • `Eat` • `Progress` • `More`

- **Today:** the home dashboard.
- **Train:** this week's plan, start any session, the exercise library, history calendar.
- **Eat:** today's meals, habits, weekly diet view, the grocery list (P1).
- **Progress:** body (weight, waist, photos), strength, consistency.
- **More:** plan editor, templates, settings, backup, about.

The workout player is a **full-screen modal flow** (no tab bar) with a persistent mini-bar if you leave it ("Strength A • 23:14 • Resume").

## 3. Screens

### 3.1 Onboarding (4 steps, skippable after step 1)
1. Welcome → "Use a ready plan" (recommended) or "Start blank".
2. About you: name, sex, age, height, current weight, goal weight, target date. Show the realistic pace (0.5–0.75 kg/week) and an estimated date. Kind, not preachy.
3. Schedule: training days (chips Mon–Sun, preselected Tue–Sat), session time, gym-closed day.
4. Food: diet type (veg / veg + eggs / non-veg / vegan), allergies and intolerances (lactose etc.), kcal and protein targets (suggested, editable).
→ Today screen, with a quick 3-card coach mark (Start, Swap, Log weight).

### 3.2 Today
- Header: greeting + date + streak chip (🔥 12) + online/offline dot.
- **Hero card:** today's session name, estimated duration, exercise count, muscle tags, a big **Start** button. On a rest day: "Rest day — 7,000 steps" with a steps ring. On Sunday: active-recovery checklist.
- **Next meal card:** time, items, protein. Buttons for "Eaten ✓", "Swap" and "Skip".
- **Rings row:** protein (g / 150), kcal, water, steps.
- **Quick log row:** Weight, Waist, Photo, Steps. Each is a bottom sheet with a stepper.
- **Coach card** (contextual): "Deload week: half the sets" / "3 lifts ready to go heavier" / "Weekly average −0.6 kg ✅".

### 3.3 Workout player (most important screen)
Layout from top to bottom:
- Top bar: ✕ (minimise), session timer, progress dots (exercise n/N), ⋯ menu (notes, reorder, end).
- Media panel (about 35% of the height): looping 2-frame demo, or the user's clip if one exists (toggle). Tap for fullscreen. A "▶ YouTube" chip shows only when online.
- Title + slot badge (A1) + superset partner hint ("then A2: Dumbbell bench press").
- Cue text, at most 2 lines, expandable.
- **Swap chip:** "Busy? → Dumbbell floor press". Tap to swap, long-press for the alternatives list.
- Target line: "3 × 8–10 • RIR 2 • rest 90 s" + last-time summary ("Last: 14 kg × 10, 10, 9").
- **Set rows:** `#`, weight stepper, reps stepper (or a timer for seconds-based exercises, a distance for metres), RIR chips (optional, collapsed), ✓ button 56 px. Completed rows turn green and are editable.
- Bottom action bar: **Log set ✓** (the big button logs the next pending row) and **Next →**.
- Rest-timer overlay: a full-width bottom sheet with a big mm:ss, −15 / +15 / Skip, and the next exercise preview. It doesn't block scrolling up to edit.
- Supersets: after logging A1 set 1, go to A2 set 1 automatically, then rest, then A1 set 2.
- Ending a session: summary (duration, total volume, sets, PRs 🏆, "go heavier" list), an optional session RPE slider (1–10), notes, then Done.
- Gestures: swipe left/right between exercises, swipe down to minimise.

### 3.4 Train tab
Week strip (Mon–Sun) with status dots, a card per day, the library (search, filter by muscle, equipment, "has my clip"), and a history calendar heatmap.

### 3.5 Exercise detail
Media (demo or clip toggle), **Record my clip** / Replace / Delete, cues, muscles, equipment, the swap mapping, a history chart (estimated 1RM), PR table, and every log entry.

### 3.6 Eat tab
Meal timeline cards (time, items, protein/kcal, state). Snack rotation chips. Running totals bar stuck to the bottom: `Protein 96/150 g • 1,240/2,000 kcal`. Habits section: water (+250 ml), oil limit ✓, creatine ✓, sleep hours.

### 3.7 Progress tab
Segmented control: Body / Strength / Consistency.
- Body: weight chart (daily dots, 7-day average line, goal line, projected date), waist chart, photo timeline with side-by-side compare.
- Strength: list of main lifts with a sparkline and Δ% over 4 weeks.
- Consistency: sessions per week bars, meal adherence %, habit streaks.

### 3.8 More
Plan editor (drag to reorder, edit sets and reps, swap mapping), Templates, Settings, Backup & restore, Storage usage (media MB), About and licences (free-exercise-db: Unlicense).

## 4. Design system
- **Theme:** dark by default (gyms are bright and screens are glary, and dark saves battery on OLED). Light theme available.
- **Colours (dark):** bg `#0B0F14`, surface `#141A22`, surface-2 `#1C2430`, text `#F2F5F8`, muted `#9AA7B4`, primary (energy orange) `#FF7A1A`, success `#2BD47D`, warning `#FFC14D`, danger `#FF5C5C`, info `#4DA3FF`. Light theme mirrors these with AA contrast.
- **Type:** Inter (self-hosted), with tabular numbers for timers and weights. Sizes: display 40/48 (timer), title 22, body 16, caption 13. No text under 13 px.
- **Spacing:** 4-pt grid. Radius 16 for cards, 12 for buttons.
- **Touch:** minimum 48×48. The primary ✓ button is 56 px. Steppers are 48 px with hold-to-repeat.
- **Motion:** 150–250 ms ease-out. Rest-timer progress ring. PR shimmer for 600 ms. Respect reduced-motion.
- **Haptics:** `navigator.vibrate` where supported (Android). Fall back to sound.
- **Icons:** lucide-react.
- **Empty states:** friendly one-liners with a single CTA.

## 5. Micro-interactions that make it feel premium
- Prefill + "same as last" chip.
- Wake Lock is held during the workout (with a visible 🔒 indicator).
- Rest timer keeps counting through screen lock (based on a timestamp) and fires a notification at 0.
- A "Resume workout" bar if the app was killed mid-session.
- Undo snackbar on every destructive action.
- An offline badge that's informative, not alarming: "Offline — everything still works".
- The PR toast appears only once per exercise per session.

## 6. Accessibility
WCAG 2.2 AA, focus rings, aria-live for timer milestones (30 s, 10 s, 0), every control labelled, Dynamic Type friendly (rem units), and colour is never the only signal.
