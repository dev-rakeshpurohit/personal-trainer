import { test, expect } from '@playwright/test';
import { dismissIntro, idbCount, onboard, unlock } from './helpers';

test('invite gate rejects a wrong code', async ({ page }) => {
  await page.goto('/today');
  await expect(page.getByRole('heading', { name: 'Repmate is invite-only' })).toBeVisible();
  await page.getByPlaceholder('RPM-XXXX-XXXX').fill('RPM-AAAA-BBBB');
  await page.getByRole('button', { name: 'Unlock' }).click();
  await expect(page.getByRole('alert')).toContainText("doesn't look right");
});

test('template onboarding → plan + diet imported into IndexedDB', async ({ page }) => {
  await onboard(page, { name: 'Alex' });
  expect(await idbCount(page, 'profile')).toBe(1);
  expect(await idbCount(page, 'programDays')).toBe(7);
  expect(await idbCount(page, 'plannedExercises')).toBeGreaterThan(25);
  expect(await idbCount(page, 'plannedMeals')).toBe(7);
  expect(await idbCount(page, 'habitDefs')).toBe(5);
  expect(await idbCount(page, 'bodyLogs')).toBe(1);
});

test('build my plan: muscle goal, 3 days, dumbbells only → generated plan without machines', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 10, 30, 8, 0) }); // Monday
  await unlock(page);
  await page.getByRole('button', { name: 'Get started' }).click(); // "Build my plan" is the default
  await page.getByRole('button', { name: /Build muscle/ }).click();
  await page.getByRole('button', { name: /Some experience/ }).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByPlaceholder('What should we call you?').fill('Priya');
  await page.getByRole('tab', { name: 'Female' }).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  // schedule: Mon / Wed / Fri, 45 min
  await page.getByRole('button', { name: 'Never' }).click();
  const day = (d: string) => page.getByRole('button', { name: d, exact: true }).first(); // training-day row comes first
  for (const d of ['Tue', 'Thu', 'Sat', 'Mon']) await day(d).click();
  await page.getByRole('button', { name: '45 min' }).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: 'Dumbbells', exact: true }).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: 'Vegetarian' }).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await expect(page.getByRole('heading', { name: 'Your plan' })).toBeVisible();
  await expect(page.getByText(/Build muscle · 3 days/)).toBeVisible();
  const preview = await page.locator('main').innerText();
  expect(preview).not.toMatch(/Leg press|Lat pulldown|Cable|Machine|Barbell/i);
  await page.getByRole('button', { name: "Let's train" }).click();
  await expect(page).toHaveURL(/today/);
  await dismissIntro(page);
  await expect(page.getByRole('heading', { level: 2, name: /Full body A/ })).toBeVisible();
  await page.getByRole('button', { name: /Start workout/ }).click();
  await expect(page.getByText('MAIN').first()).toBeVisible();
});
