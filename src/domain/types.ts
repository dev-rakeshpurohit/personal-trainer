// Shared domain types (doc 04). Pure TS, no React.
export type Unit = 'reps' | 'seconds' | 'minutes' | 'meters';
export type DayType = 'strength' | 'cardio' | 'conditioning' | 'rest' | 'active_recovery';
export type Weekday = 'MON' | 'TUE' | 'WED' | 'THU' | 'FRI' | 'SAT' | 'SUN';
export type Sex = 'male' | 'female' | 'other';
export type DietType = 'veg' | 'veg_egg' | 'nonveg' | 'vegan';

export interface Profile {
  id: 'me';
  name: string;
  sex: Sex;
  birthYear: number;
  heightCm: number;
  startWeightKg: number;
  goalWeightKg: number;
  targetDate?: string;
  units: 'kg' | 'lb';
  theme: 'dark' | 'light' | 'system';
  dietType: DietType;
  intolerances: string[];
  kcalTarget: number;
  proteinTargetG: number;
  trainingDays: Weekday[];
  sessionTime: string;
  restTimer: { sound: boolean; vibrate: boolean; notify: boolean };
  stepKg: { dumbbell: number; barbell: number; machine: number };
  weekStart: 'mon' | 'sun';
  createdAt: string;
}

export type Category = 'strength' | 'cardio' | 'mobility' | 'power' | 'core';

export interface Exercise {
  id: string;
  name: string;
  freeDbId?: string;
  primaryMuscles: string[];
  equipment: string[];
  category: Category;
  cue?: string;
  instructions?: string[];
  youtubeQuery?: string;
  custom: boolean;
  isBodyweight?: boolean;
  defaultUnit: Unit;
}

export interface CycleEntry {
  weeks: number[];
  rir: number;
  deload?: boolean;
  note?: string;
}
export interface ProgressionCfg {
  model: 'double_progression';
  dumbbellIncrementKg: number;
  barIncrementKg: number;
  cycle: CycleEntry[];
}
export interface WarmupItem {
  name: string;
  minutes?: number;
  reps?: string;
  exerciseId?: string;
}

export interface Program {
  id: string;
  name: string;
  active: boolean;
  startedOn: string;
  warmup: WarmupItem[];
  cooldown: string;
  rules: string[];
  progression: ProgressionCfg;
  templateId?: string;
}

export interface ProgramDay {
  id: string;
  programId: string;
  weekday: Weekday;
  type: DayType;
  title: string;
  durationMin?: number;
  notes?: string;
  order: number;
}

export interface PlannedExercise {
  id: string;
  dayId: string;
  order: number;
  slot: string;
  exerciseId: string;
  swapExerciseId?: string;
  supersetGroup?: string;
  sets: number;
  repsMin: number;
  repsMax: number;
  unit: Unit;
  perSide: boolean;
  restSec: number;
  cue?: string;
}

export interface Session {
  id: string;
  dayKey: string;
  programDayId?: string;
  title: string;
  startedAt: string;
  endedAt?: string;
  status: 'active' | 'done' | 'abandoned';
  rpe?: number;
  notes?: string;
  cycleWeek: number;
  deload: boolean;
}

export interface SetLog {
  id: string;
  sessionId: string;
  exerciseId: string;
  plannedExerciseId?: string;
  swappedFromExerciseId?: string;
  setIndex: number;
  weightKg?: number;
  reps?: number;
  seconds?: number;
  meters?: number;
  rir?: number;
  completedAt: string;
  isWarmup: boolean;
}

export interface ActiveSessionState {
  id: 'current';
  sessionId: string;
  exerciseIdx: number;
  setIdx: number;
  restEndsAt?: string;
  restTotalSec?: number;
  swaps: Record<string, string>;
  extraSets?: Record<string, number>;
}

export interface DietPlan {
  id: string;
  name: string;
  active: boolean;
  kcalTarget: number;
  proteinTargetG: number;
}
export interface PlannedMeal {
  id: string;
  dietPlanId: string;
  order: number;
  time: string;
  meal: string;
  items: string[];
  rotate?: string[];
  proteinG: number;
  kcal: number;
  optional?: boolean;
  skipOnRestDay?: boolean;
}
export interface MealLog {
  id: string;
  dayKey: string;
  plannedMealId?: string;
  state: 'eaten' | 'swapped' | 'skipped';
  label?: string;
  proteinG: number;
  kcal: number;
  chosenRotation?: string;
  loggedAt: string;
}

export interface HabitDef {
  id: string;
  label: string;
  kind: 'check' | 'number';
  target?: number;
  unit?: string;
  order: number;
}
export interface HabitLog {
  id: string;
  dayKey: string;
  habitId: string;
  value: number;
}

export interface BodyLog {
  id: string;
  dayKey: string;
  weightKg?: number;
  waistCm?: number;
  note?: string;
}
export type Pose = 'front' | 'side' | 'back';
export interface Photo {
  id: string;
  dayKey: string;
  pose: Pose;
  blobId: string;
}
export interface MediaBlob {
  id: string;
  kind: 'clip' | 'photo';
  mime: string;
  bytes: number;
  blob: Blob;
  createdAt: string;
}
export interface ExerciseClip {
  exerciseId: string;
  blobId: string;
  durationSec: number;
  thumb?: string;
}
export interface Meta {
  key: string;
  value: unknown;
}

export const WEEKDAYS: Weekday[] = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
export const WEEKDAY_LABEL: Record<Weekday, string> = {
  MON: 'Mon',
  TUE: 'Tue',
  WED: 'Wed',
  THU: 'Thu',
  FRI: 'Fri',
  SAT: 'Sat',
  SUN: 'Sun',
};
export const isTrainingType = (t: DayType) => t === 'strength' || t === 'cardio' || t === 'conditioning';
