# Repfellow Flutter UI conventions (read before building any screen)

**Product spec:** `/Users/rakeshpurohit/RONY/DEV/PERSONAL/reports/Repmate UX competitor analysis.md`. The product is now called **Repfellow**; the report still says Repmate. The owner's decisions are at the bottom of `docs/DECISIONS.md`.

## Owner decisions (binding)
- **Tabs:** 5 (Today · Train · Eat · Progress · Coach), no social feed.
- **Trainer codes:** 30% off for the client, 25% recurring share for the trainer.
- **Paywall:** soft, after the plan reveal, shown once, with a timeline. Never shown to trainer or promo users.
- **Language:** English UI; Hinglish accepted in free-text and voice input.
- **Scope:** "build first, test on TestFlight". Real in-app purchase (StoreKit/RevenueCat), accounts and trainer mode come later: show UI where the spec needs it, but keep logic local and mark beta stubs clearly.

## Imports and design system
- Material: `import 'package:material_ui/material_ui.dart';` (`package:flutter/material.dart` is deprecated).
- Icons: `import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;` and Material `Icons`.
- Tokens: `context.rf` (`RfColors`: bg, surface, surface2, line, text, muted, accent [marigold fill], accentInk [marigold text], onAccent, done [leaf], pr [gold], coach [violet, AI], trainer [teal], caution [amber], destructive [the only red]).
  - `RfType`: timer, setNumeral, title, headline, body, bodyStrong, callout, caption, captionStrong, overline (numerals use tabular figures).
  - `Rf`: gutter 16, cardRadius 20, btnRadius 14, tap 48, gymTap 56, doneBar 64.
- **Shared widgets in `lib/ui/widgets.dart`:** RfButton (kinds primary/secondary/ghost/coach/destructive), DoneBar, RfCard, Pressable, SectionTitle, PageHeader, RfChip, ReasonChip, CoachDot, TrainerMark, StatusPill, BigStepper, ProgressRing, LinearMeter, EmptyState, showRfToast (with Undo), showRfSheet.
- Haptics: `lib/ui/haptics.dart`. Demos: `lib/ui/demo_player.dart` (`DemoPlayer`, `ExerciseThumb`).
- Don't edit `lib/ui/*`, `lib/app/*`, `lib/domain/*`, `lib/data/*`, `lib/state/*` or `pubspec.yaml`. If you need a shared widget, put it in your own feature folder. If you need a dependency or a change in a shared file, say so in your final reply and I'll do it.

## Rules from the spec
- **No hard-coded colours.**
  - One accent per screen.
  - Violet marks anything the AI authored, teal anything the trainer did.
  - Never red for misses or macros.
  - Every state shows an icon or a label, not colour alone.
- **Tap targets:** at least 48, and 56–64 on the gym floor. Primary actions go in the thumb zone. Use steppers, not keyboards, for set values.
- **Words before numbers.** Every chart gets a one-line meaning.
- **Propose, never impose.** AI changes are diffs the user approves, and every change can be undone.
- **Copy:** no "failed", "missed your goal" or "streak lost". Plain, warm English.
- **Accessibility:** Semantics labels on custom controls, and support for Dynamic Type (`MediaQuery.textScaler`). Honour Reduce Motion (`context.reduceMotion`).
- **Safe areas:** the tab bar is translucent and the Scaffold uses `extendBody`. Because of `extendBody`, `MediaQuery.paddingOf(context).bottom` inside a tab body already includes the tab bar, so pad scrollable content by that value + 16. Do not add `kTabBarHeight` again.

## Data
- Riverpod 3 providers live in `lib/state/providers.dart`; read the file for exact names. Services are in `lib/data/services/*`, models and pure logic in `lib/domain/*`.
- The UI never writes to the DB directly; it goes through services (`repoProvider`, `sessionServiceProvider`, `planEditProvider`, `planBuilderProvider`, `coachClientProvider`…).
- Dates: use `clockProvider` for "now" so tests can control time.

## Navigation
- Routes in go_router: `/today`, `/train`, `/eat`, `/progress`, `/coach` (tabs), `/workout` (full-screen logger), `/onboarding` (`?fresh=1` to redo setup).
- Sub-screens inside a feature use `Navigator.of(context).push(MaterialPageRoute(...))` so nobody edits the router. Cross-feature links use `context.go(...)` / `context.push(...)` with the routes above.

## Tests
- Widget tests go in `test/features/<feature>/`. Use `ProviderScope(overrides: [storesProvider.overrideWithValue(...)])` with an in-memory DB, following `test/data/harness.dart` and `test/state/providers_test.dart`.
- Seed demo data with `seedDemoData` from `lib/data/services/dev_seed.dart`.
- Run `flutter test test/features/<feature>` and `dart analyze lib/features/<feature> test/features/<feature>`. Both must be clean.
