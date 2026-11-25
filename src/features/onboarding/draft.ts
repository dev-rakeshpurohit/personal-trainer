import { PRESETS } from '@/domain/equipment';
import type { DietType, Experience, Goal, Profile, Sex, Weekday } from '@/domain/types';

export interface SetupDraft {
  name: string;
  sex: Sex;
  age: number;
  heightCm: number;
  weightKg: number;
  goalKg: number;
  waistCm?: number;
  targetDate: string;
  goal: Goal;
  experience: Experience;
  days: Weekday[];
  closed: Weekday | '';
  sessionTime: string;
  sessionMin: number;
  equipment: string[];
  diet: DietType;
  intolerances: string[];
  kcal?: number;
  protein?: number;
}

export const defaultDraft = (): SetupDraft => ({
  name: '',
  sex: 'male',
  age: 30,
  heightCm: 175,
  weightKg: 80,
  goalKg: 74,
  targetDate: '',
  goal: 'lean',
  experience: 'beginner',
  days: ['TUE', 'WED', 'THU', 'FRI', 'SAT'],
  closed: 'MON',
  sessionTime: '09:15',
  sessionMin: 60,
  equipment: [...PRESETS.full_gym],
  diet: 'veg_egg',
  intolerances: ['lactose'],
});

export function draftFromProfile(p: Profile): SetupDraft {
  return {
    name: p.name,
    sex: p.sex,
    age: new Date().getFullYear() - p.birthYear,
    heightCm: p.heightCm,
    weightKg: p.startWeightKg,
    goalKg: p.goalWeightKg,
    targetDate: p.targetDate ?? '',
    goal: p.goal ?? 'lean',
    experience: p.experience ?? 'beginner',
    days: p.trainingDays,
    closed: '',
    sessionTime: p.sessionTime,
    sessionMin: p.sessionMin ?? 75,
    equipment: p.equipment ?? [...PRESETS.full_gym],
    diet: p.dietType,
    intolerances: p.intolerances,
    kcal: p.kcalTarget,
    protein: p.proteinTargetG,
  };
}

export function profileFromDraft(d: SetupDraft, base: Partial<Profile> = {}): Profile {
  return {
    id: 'me',
    units: 'kg',
    theme: 'dark',
    restTimer: { sound: true, vibrate: true, notify: false },
    stepKg: { dumbbell: 2, barbell: 5, machine: 5 },
    weekStart: 'mon',
    createdAt: new Date().toISOString(),
    ...base,
    name: d.name.trim() || base.name || 'there',
    sex: d.sex,
    birthYear: new Date().getFullYear() - d.age,
    heightCm: d.heightCm,
    startWeightKg: d.weightKg,
    goalWeightKg: d.goalKg,
    targetDate: d.targetDate || undefined,
    dietType: d.diet,
    intolerances: d.intolerances,
    kcalTarget: d.kcal ?? base.kcalTarget ?? 2000,
    proteinTargetG: d.protein ?? base.proteinTargetG ?? 140,
    trainingDays: d.days.length ? d.days : ['TUE', 'THU', 'SAT'],
    sessionTime: d.sessionTime,
    goal: d.goal,
    experience: d.experience,
    sessionMin: d.sessionMin,
    equipment: d.equipment,
  };
}
