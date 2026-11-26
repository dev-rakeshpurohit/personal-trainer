import { expect, test } from '@playwright/test';
import { onboard } from './helpers';

const PLAN = {
  summary: 'Three knee-friendly full-body days with simple vegetarian meals.',
  workout: {
    name: 'Knee-friendly 3-day',
    days: [
      {
        weekday: 'TUE', type: 'strength', title: 'Full body A', durationMin: 60,
        exercises: [
          { id: 'dumbbell-box-squat-to-bench', sets: 3, repsMin: 8, repsMax: 10, unit: 'reps', restSec: 90 },
          { id: 'lat-pulldown', sets: 3, repsMin: 10, repsMax: 12, unit: 'reps', restSec: 75 },
          { id: 'made-up-exercise', sets: 3, repsMin: 10, repsMax: 12, unit: 'reps', restSec: 75 },
        ],
      },
      { weekday: 'THU', type: 'strength', title: 'Full body B', durationMin: 60, exercises: [{ id: 'leg-press', sets: 3, repsMin: 10, repsMax: 12, unit: 'reps', restSec: 90 }] },
    ],
  },
  diet: {
    kcalTarget: 2000,
    proteinTargetG: 140,
    meals: [
      { time: '08:00', meal: 'Breakfast', items: ['3 eggs', '1 roti'], kcal: 500, proteinG: 30 },
      { time: '13:00', meal: 'Lunch', items: ['Paneer 100 g', 'Dal 1 bowl', '2 roti'], kcal: 800, proteinG: 55 },
      { time: '20:00', meal: 'Dinner', items: ['Curd 200 g', 'Rajma 1 bowl', 'Rice 1 cup'], kcal: 700, proteinG: 55 },
    ],
  },
};

test('AI coach: describe a change, preview, apply; unknown exercises are dropped', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 1, 8) });
  await onboard(page);
  let sent: { code: string; notes: string; exercises: { id: string }[]; current?: string } | undefined;
  await page.route('**/api/coach', async (route) => {
    sent = route.request().postDataJSON();
    await route.fulfill({ json: { plan: PLAN, model: 'test', costUsd: 0.0042 } });
  });
  await page.goto('/more/coach');
  await expect(page.getByRole('heading', { name: 'AI coach' })).toBeVisible();
  // the invite code entered at the gate is reused: no code field
  await expect(page.getByPlaceholder('RPM-XXXX-XXXX')).toHaveCount(0);
  await page.getByRole('textbox').fill('My knee hurts on lunges');
  await page.getByRole('button', { name: /Update my plan/ }).click();
  await expect(page.getByText('Three knee-friendly full-body days')).toBeVisible();
  await expect(page.getByText('US$0.0042')).toBeVisible();
  await expect(page.getByText(/made-up-exercise/)).toBeVisible(); // warning about the dropped id
  expect(sent!.notes).toBe('My knee hurts on lunges');
  expect(sent!.current).toContain('dumbbell-goblet-squat');
  expect(sent!.exercises.length).toBeGreaterThan(300);
  await page.getByRole('button', { name: 'Use this plan' }).click();
  await expect(page).toHaveURL(/\/train/);
  await expect(page.getByRole('button', { name: /Full body A/ }).first()).toBeVisible();
  await page.getByRole('link', { name: 'Eat' }).click();
  await expect(page.getByText(/Paneer 100 g/).first()).toBeVisible();
});

test('AI coach: offline-safe errors keep the request', async ({ page }) => {
  await onboard(page);
  await page.route('**/api/coach', (route) => route.fulfill({ status: 429, json: { error: 'The coach needs a breather. Try again in a little while.' } }));
  await page.goto('/more/coach');
  await page.getByRole('textbox').fill('Shorter Fridays');
  await page.getByRole('button', { name: /Update my plan/ }).click();
  await expect(page.getByRole('alert')).toContainText('needs a breather');
  await expect(page.getByRole('textbox')).toHaveValue('Shorter Fridays');
});

test('Plan check finds the calf gap and adds a calf raise in one tap', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 1, 8) });
  await onboard(page);
  await page.getByRole('link', { name: 'Train' }).click();
  await page.getByRole('button', { name: /Plan check/ }).click();
  await expect(page.getByRole('dialog')).toContainText('Calves: 0 of', { timeout: 20_000 });
  await page.getByRole('dialog').getByRole('button', { name: /^Add to / }).first().click();
  await expect(page.getByRole('dialog').getByRole('button', { name: 'Added' })).toBeVisible();
  await page.getByRole('button', { name: 'Close' }).last().click();
  await expect(page.getByRole('button', { name: /Plan check/ })).toContainText('Every muscle group', { timeout: 15_000 });
});
