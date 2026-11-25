import Dexie, { type Table } from 'dexie';
import type {
  ActiveSessionState, BodyLog, DietPlan, Exercise, ExerciseClip, HabitDef, HabitLog, MealLog, MediaBlob, Meta, Photo,
  PlannedExercise, PlannedMeal, Profile, Program, ProgramDay, Session, SetLog,
} from '@/domain/types';

export class RepmateDB extends Dexie {
  profile!: Table<Profile, string>;
  exercises!: Table<Exercise, string>;
  programs!: Table<Program, string>;
  programDays!: Table<ProgramDay, string>;
  plannedExercises!: Table<PlannedExercise, string>;
  sessions!: Table<Session, string>;
  sets!: Table<SetLog, string>;
  activeSession!: Table<ActiveSessionState, string>;
  dietPlans!: Table<DietPlan, string>;
  plannedMeals!: Table<PlannedMeal, string>;
  mealLogs!: Table<MealLog, string>;
  habitDefs!: Table<HabitDef, string>;
  habitLogs!: Table<HabitLog, string>;
  bodyLogs!: Table<BodyLog, string>;
  photos!: Table<Photo, string>;
  media!: Table<MediaBlob, string>;
  clips!: Table<ExerciseClip, string>;
  meta!: Table<Meta, string>;

  constructor(name = 'repmate') {
    super(name);
    this.version(1).stores({
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
  }
}

export const db = new RepmateDB();

/** Tables exported in a backup (in restore order). */
export const DATA_TABLES = [
  'profile', 'exercises', 'programs', 'programDays', 'plannedExercises', 'sessions', 'sets', 'activeSession',
  'dietPlans', 'plannedMeals', 'mealLogs', 'habitDefs', 'habitLogs', 'bodyLogs', 'photos', 'clips', 'meta',
] as const;
export type DataTable = (typeof DATA_TABLES)[number];

export const uid = (): string =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export async function getMeta<T>(key: string): Promise<T | undefined> {
  return (await db.meta.get(key))?.value as T | undefined;
}
export async function setMeta(key: string, value: unknown): Promise<void> {
  await db.meta.put({ key, value });
}
