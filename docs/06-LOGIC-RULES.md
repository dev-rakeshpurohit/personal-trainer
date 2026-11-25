# 06 — Business Logic Rules (implement in `src/domain/`, unit-test everything)

## 1. Schedule
- `getDayPlan(date)`: find the active program's `ProgramDay` by weekday. If there's none, it's a rest day.
- `cycleWeek(date) = floor(daysSince(program.startedOn) / 7) % 8 + 1`.
- Week 8 is a **deload**: the planned sets become `ceil(sets / 2)` and loads stay the same. Show a banner.
- If a training day is missed, don't shift the plan automatically. Offer "Do Tuesday's session today?" (P1 week planner).

## 2. Double progression (per planned exercise, per exercise actually done)
Inputs: the last completed session's working sets for this `exerciseId`, plus the planned `repsMax`, `sets` and target RIR for this cycle week (from `program.progression.cycle`).
```
readyToProgress =
  workingSets.length >= plannedSets &&
  every set: reps >= repsMax && (rir == null || rir >= targetRIR - 0)
suggestion:
  if readyToProgress → weight = lastWeight + increment(equipment)   // dumbbell 2, barbell/trap 5, machine 5 (per profile.stepKg)
                        reps target = repsMin
  else if any set reps < repsMin for 2 consecutive sessions → suggest −1 increment (show as "Ease off" note)
  else → same weight, aim +1 rep on the lowest set
```
- For seconds-based exercises (plank etc.), progress the time: once every set hits `repsMax` seconds, add 5–10 s to the targets, capped at 60 s (then suggest a harder variant).
- Prefill: weight = the suggestion, reps = last reps for that set index (or `repsMin`).
- Swap exercises keep their **own** history (keyed by `exerciseId`).

## 3. Strength metrics
- Estimated 1RM (Epley) = `w × (1 + reps/30)` for reps ≤ 12. Ignore reps > 12 for e1RM.
- PR types: heaviest weight, best e1RM, most reps at a given weight. A PR is detected when a set completes, and the toast shows once per exercise per session.
- Volume = Σ weight × reps (working sets only).

## 4. Body weight trend
- `weeklyAverage(weekStart)` = the mean of weigh-ins in that ISO week. Valid only with at least 4 entries; otherwise show "need n more weigh-ins".
- `rateKgPerWeek` = the slope of a linear regression over the last 21 days of daily weights (needs ≥ 10 points). Fall back to the difference between consecutive valid weekly averages.
- `projectedGoalDate = today + (current7dAvg − goal) / rate` weeks, only when rate > 0.1. Display it as a month and day, never with false precision.
- Chart: raw dots (faint), 7-day moving average (bold), goal line, target date marker.

## 5. Diet totals
- Day totals = Σ `MealLog` (eaten/swapped use the planned values unless edited; skipped = 0).
- Rest day (the program day's type is `rest` or `active_recovery`) hides meals with `skipOnRestDay`.
- Rings: protein vs target, kcal vs target (show as "remaining").
- Adherence % = eaten-or-swapped non-optional meals ÷ planned non-optional meals.

## 6. Diet adjustment coach (every 14 days, after ≥ 14 days of data)
Use `seed/diet.*.json → adjustmentRules`:
| Condition | Card |
|---|---|
| rate between 0.5 and 0.75 kg/week | "On track ✅ — no change" |
| rate < 0.3 for 2 consecutive weekly checks **and** adherence ≥ 80% | "Add 2,000 steps/day first. If still stuck next check: lunch rice → 50 g (≈ −65 kcal)" |
| rate < 0.3 with adherence < 80% | "Adherence first: you hit {x}% of meals" (no calorie cut) |
| rate > 1.0 or e1RM on ≥ 2 main lifts down > 5% over 3 weeks | "Eat a bit more: rice back to 100 g or +1 toast (≈ +70 kcal)" |
- The user can tap **Apply**, which edits the plan's meal (and logs the change in `meta.planChanges`), or **Dismiss**.
- Never suggest below 1,700 kcal for a male or 1,400 for a female without a "talk to a professional" note.

## 7. Streaks and consistency
- Training streak = consecutive **planned** training days completed. Rest days don't break it, but a missed planned day does.
- Weekly target ring = sessions done ÷ planned sessions.

## 8. Reminders (P1)
- Default times: pre-gym 08:30 (training days), weigh-in 07:30, water every 2 h from 10:00 to 20:00 (opt-in), backup on the 1st of the month.
- Implemented via SW `showNotification`, scheduled while the app is open (there's no reliable background scheduling in PWAs). Document this limitation in Settings.
