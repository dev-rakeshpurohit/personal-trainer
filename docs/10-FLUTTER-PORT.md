# 10 — Native app in Flutter

**Decision (2026-11-26):** The owner chose Flutter for the native iOS/Android app, over Capacitor and React Native. The PWA (`/src`) stays live and is the behavioural reference. The Flutter app lives in `/mobile` and shares the same seeds, demo media and the `/api/coach` endpoint.

## Stack
- Flutter 3.50 (stable), Dart 3.14. SDK at `~/development/flutter`. Swift Package Manager is enabled; CocoaPods is not installed and is only needed if a plugin requires it.
- State: Riverpod 3. Routing: go_router (tab shell + full-screen routes).
- Offline data: drift (SQLite). Tables mirror the Dexie stores and keep the JSON shape, so backups stay compatible with the web app.
- Native features:
  - Notifications and rest timer: `flutter_local_notifications` (on time even when locked).
  - Haptics: `HapticFeedback`.
  - Screen: `wakelock_plus`.
  - Files and media: `share_plus`, `file_picker`, `image_picker`, `video_player`.
  - Later: `health` for Apple Health / Health Connect, and `purchases_flutter` (RevenueCat).
- Charts: `fl_chart`. Network: `http`, for the AI coach only.

## Layout (`mobile/lib`)
- `domain/`: pure Dart ports of `src/domain/*.ts`, one file per module (snake_case), with tests in `test/domain/`. No Flutter imports.
- `data/`: drift database, repositories, seed import, library builder, plan builder, backup.
- `features/<area>/`: screens (today, train, workout, eat, progress, history, library, plan_editor, coach, settings, onboarding, backup, more).
- `ui/`: theme tokens (same colours as the PWA, dark by default) and shared widgets (Stepper, Sheet, Ring, Segmented, Chip, DemoPlayer).
- `app.dart`, `router.dart`, `main.dart`.
- `assets/`: seeds (copied by `tool/sync_assets.dart`) and `media/demos` (git-ignored, Gym Visual licence, personal use only).

## Apple account safety (owner's request, 2026-11-26)
The developer account also hosts a client's app. Repmate uses its own bundle ID and app record. Never revoke or delete certificates or profiles, and never touch other apps. If signing asks to revoke anything, stop and ask the owner.

## Porting rules
- Behaviour must match the TypeScript module. Port its unit tests too; same cases, same numbers.
- JSON wire values stay identical (enums expose `.wire`).
- Pure functions take dates explicitly. Never read `DateTime.now()` inside `domain/`.

## Milestones
- [x] F0 Project, dependencies, models, schedule and units.
- [x] F1 Domain port: progression, stats, diet, coach, sessionFlow, sessionPlan, replan, equipment, generator, balance, dietGen, aiPlan. All tests green: 332 tests. Fuzz parity checks against the TS found zero differences (generator 2,430 programs, Plan check, diet generator 600 inputs, AI normaliser 3,000 replies).
- [x] F2 Data layer: drift store, seed import + library builder (1,320 exercises), asset sync, services (plan builder, session engine, repo, backup, coach client, dev seed) and Riverpod providers. 390 tests.
- [x] **UX0 UX/UI competitor research and Repmate UX spec** (reports/Repmate UX competitor analysis.md; owner decisions in DECISIONS.md, 2026-11-26). This sets the selling point, personas, end-to-end user journeys, information architecture, key flows and design system. It is the owner's #1 priority: the journey and UX are the product's differentiator. Screens F3–F7 follow this spec, not the PWA layout. The PWA is only the reference for behaviour and logic.
- [ ] F3 App shell: theme, tabs, gate, onboarding (template, generated, blank), Today.
- [ ] F4 Workout loop: prestart, player (log set, rest timer with notification and haptics, swaps/alternates), summary and feedback. First TestFlight build at this point.
- [ ] F5 Train, library with 3D demos, exercise detail, plan editor, Plan check.
- [ ] F6 Eat, habits, diet editor, progress charts, history, body and photos, clips.
- [ ] F7 AI coach, settings, setup, backup/restore (web-compatible), storage, about.
- [ ] F8 Polish, App Store assets, privacy, TestFlight external, Android.
