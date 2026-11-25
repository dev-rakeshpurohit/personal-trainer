# 04 — Data Model (Dexie / IndexedDB)

All ids are `crypto.randomUUID()` unless stated. Dates are ISO strings; `dayKey` is `YYYY-MM-DD` in the device's local time. Weights are stored in **kg** and converted for display only.

## TypeScript types
```ts
type Unit = 'reps' | 'seconds' | 'minutes' | 'meters';
type DayType = 'strength' | 'cardio' | 'conditioning' | 'rest' | 'active_recovery';
type Weekday = 'MON'|'TUE'|'WED'|'THU'|'FRI'|'SAT'|'SUN';

interface Profile {
  id: 'me'; name: string; sex: 'male'|'female'|'other'; birthYear: number;
  heightCm: number; startWeightKg: number; goalWeightKg: number; targetDate?: string;
  units: 'kg'|'lb'; theme: 'dark'|'light'|'system';
  dietType: 'veg'|'veg_egg'|'nonveg'|'vegan'; intolerances: string[]; // e.g. ['lactose']
  kcalTarget: number; proteinTargetG: number;
  trainingDays: Weekday[]; sessionTime: string; // '09:15'
  restTimer: { sound: boolean; vibrate: boolean; notify: boolean };
  stepKg: { dumbbell: number; barbell: number; machine: number }; // 2, 5, 5
  createdAt: string;
}

interface Exercise {            // library entry
  id: string;                   // slug, e.g. 'goblet-squat'
  name: string; freeDbId?: string; // maps to /media/exercises/<freeDbId>/{0,1}.jpg
  primaryMuscles: string[]; equipment: string[]; category: 'strength'|'cardio'|'mobility'|'power'|'core';
  cue?: string; youtubeQuery?: string; custom: boolean;
  isBodyweight?: boolean; defaultUnit: Unit;
}

interface Program { id: string; name: string; active: boolean; startedOn: string; // for 8-week cycle
  warmup: WarmupItem[]; cooldown: string; rules: string[]; progression: ProgressionCfg; }

interface ProgramDay { id: string; programId: string; weekday: Weekday; type: DayType;
  title: string; durationMin?: number; notes?: string; order: number; }

interface PlannedExercise { id: string; dayId: string; order: number; slot: string; // 'A1'
  exerciseId: string; swapExerciseId?: string; supersetGroup?: string;
  sets: number; repsMin: number; repsMax: number; unit: Unit; perSide: boolean;
  restSec: number; cue?: string; }

interface Session { id: string; dayKey: string; programDayId?: string; title: string;
  startedAt: string; endedAt?: string; status: 'active'|'done'|'abandoned';
  rpe?: number; notes?: string; cycleWeek: number; deload: boolean; }

interface SetLog { id: string; sessionId: string; exerciseId: string;  // the exercise actually done
  plannedExerciseId?: string; swappedFromExerciseId?: string;
  setIndex: number; weightKg?: number; reps?: number; seconds?: number; meters?: number;
  rir?: number; completedAt: string; isWarmup: boolean; }

interface ActiveSessionState { id: 'current'; sessionId: string; exerciseIdx: number; setIdx: number;
  restEndsAt?: string; swaps: Record<string /*plannedExerciseId*/, string /*exerciseId*/>; }

interface DietPlan { id: string; name: string; active: boolean; kcalTarget: number; proteinTargetG: number; }
interface PlannedMeal { id: string; dietPlanId: string; order: number; time: string; meal: string;
  items: string[]; rotate?: string[]; proteinG: number; kcal: number; optional?: boolean; skipOnRestDay?: boolean; }
interface MealLog { id: string; dayKey: string; plannedMealId?: string; state: 'eaten'|'swapped'|'skipped';
  label?: string; proteinG: number; kcal: number; chosenRotation?: string; loggedAt: string; }

interface HabitDef { id: string; label: string; kind: 'check'|'number'; target?: number; unit?: string; order: number; }
interface HabitLog { id: string; dayKey: string; habitId: string; value: number; } // check → 1/0

interface BodyLog { id: string; dayKey: string; weightKg?: number; waistCm?: number; note?: string; }
interface Photo { id: string; dayKey: string; pose: 'front'|'side'|'back'; blobId: string; }
interface MediaBlob { id: string; kind: 'clip'|'photo'; mime: string; bytes: number; blob: Blob; createdAt: string; }
interface ExerciseClip { exerciseId: string; blobId: string; durationSec: number; }

interface Meta { key: string; value: unknown; } // lastBackupAt, schemaVersion, seenCoachMarks…
```

## Dexie schema (v1)
```ts
db.version(1).stores({
  profile: 'id',
  exercises: 'id, name, freeDbId, *primaryMuscles, custom',
  programs: 'id, active',
  programDays: 'id, programId, weekday, [programId+weekday]',
  plannedExercises: 'id, dayId, [dayId+order], exerciseId',
  sessions: 'id, dayKey, status, programDayId, startedAt',
  sets: 'id, sessionId, exerciseId, [exerciseId+completedAt], completedAt',
  activeSession: 'id',
  dietPlans: 'id, active',
  plannedMeals: 'id, dietPlanId, [dietPlanId+order]',
  mealLogs: 'id, dayKey, plannedMealId, [dayKey+plannedMealId]',
  habitDefs: 'id, order',
  habitLogs: 'id, dayKey, habitId, [dayKey+habitId]',
  bodyLogs: 'id, &dayKey',
  photos: 'id, dayKey',
  media: 'id, kind, createdAt',
  clips: 'exerciseId',
  meta: 'key',
});
```

## Seed mapping
- `seed/program.lean-athletic-v2.json` → `programs`, `programDays`, `plannedExercises`, plus an `exercises` upsert for each exercise and swap (slug from the name; keep `freeDbId`, `youtubeQuery`, `cue`).
- `seed/diet.lean-veg-egg-2000.json` → `dietPlans`, `plannedMeals`, `habitDefs`. `adjustmentRules` and `annualChecks` are stored in `meta`.
- Profile defaults are **not** seeded. They come from onboarding.

## Backup format
```json
{ "app": "repmate", "schemaVersion": 1, "exportedAt": "…", "tables": { "profile": [...], "sessions": [...], … },
  "media": "omitted" | "included-in-zip" }
```
Validate it with zod on import. Offer merge or replace.
