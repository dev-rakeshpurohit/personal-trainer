import { test, expect } from '@playwright/test';
import { idbCount, onboard } from './helpers';

test('fresh install → onboarding → template imported into IndexedDB', async ({ page }) => {
  await page.goto('/today');
  await expect(page).toHaveURL(/\/onboarding/);
  await onboard(page, { name: 'Alex' });
  expect(await idbCount(page, 'profile')).toBe(1);
  expect(await idbCount(page, 'programDays')).toBe(7);
  expect(await idbCount(page, 'plannedExercises')).toBeGreaterThan(25);
  expect(await idbCount(page, 'plannedMeals')).toBe(7);
  expect(await idbCount(page, 'habitDefs')).toBe(5);
  expect(await idbCount(page, 'bodyLogs')).toBe(1);
});
