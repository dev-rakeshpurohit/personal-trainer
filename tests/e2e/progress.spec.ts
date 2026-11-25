import { test, expect } from '@playwright/test';
import { onboard } from './helpers';

test.beforeEach(async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 20, 8, 0) });
  await onboard(page);
  await page.goto('/more/dev');
  await page.getByRole('button', { name: 'Load 30 days of demo data' }).click();
  await expect(page).toHaveURL(/progress/);
});

test('30 days of data: body charts, stats and the diet coach render', async ({ page }) => {
  await expect(page.getByText('7-day average', { exact: true })).toBeVisible();
  await expect(page.getByRole('img', { name: /Weight chart/ }).locator('svg.recharts-surface')).toBeVisible();
  await expect(page.locator('.recharts-scatter-symbol').first()).toBeVisible();
  await expect(page.getByText(/kg\/wk/)).toBeVisible();
  await expect(page.getByText(/Diet check/)).toBeVisible();
  await expect(page.getByRole('img', { name: 'Waist trend' })).toBeVisible();
});

test('strength + consistency tabs render trends', async ({ page }) => {
  await page.getByRole('tab', { name: 'Strength' }).click();
  await expect(page.getByText('Lifts · 4-week change')).toBeVisible();
  await expect(page.getByRole('link', { name: /Dumbbell goblet squat/ })).toBeVisible();
  await page.getByRole('tab', { name: 'Consistency' }).click();
  await expect(page.getByRole('img', { name: 'Sessions per week' }).locator('.recharts-rectangle').first()).toBeVisible();
  await expect(page.getByText('Habit streaks')).toBeVisible();
});

test('today shows go-heavier coach card and backup reminder', async ({ page }) => {
  await page.getByRole('link', { name: 'Today' }).click();
  await expect(page.getByText(/ready to go heavier|Weekly average/).first()).toBeVisible();
  await expect(page.getByText('Time for your monthly backup')).toBeVisible();
});

test('history: calendar → day detail → delete session with undo', async ({ page }) => {
  await page.goto('/train/history');
  const workoutDay = page.locator('a[aria-label*="Strength"]').first();
  await workoutDay.click();
  await expect(page).toHaveURL(/history\/\d{4}-\d{2}-\d{2}/);
  const del = page.getByRole('button', { name: /^Delete Strength/ });
  await del.click();
  await expect(del).toHaveCount(0);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.getByRole('button', { name: /^Delete Strength/ })).toBeVisible();
});
