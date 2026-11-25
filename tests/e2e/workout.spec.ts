import { test, expect, type Page } from '@playwright/test';
import { idbCount, onboard } from './helpers';

const TUESDAY = new Date(2026, 11, 1, 9, 15);

async function startToday(page: Page) {
  await page.getByRole('button', { name: /Start workout/ }).click();
  await expect(page).toHaveURL(/\/workout\/today/);
  await page.getByRole('button', { name: /Begin workout/ }).click();
  await expect(page).toHaveURL(/\/workout$/);
}

test('log sets with superset flow, rest timer, and resume after reload', async ({ page }) => {
  await page.clock.install({ time: TUESDAY });
  await onboard(page);
  await startToday(page);

  await expect(page.getByRole('heading', { level: 1, name: 'Dumbbell goblet squat' })).toBeVisible();
  await expect(page.getByText('Superset: then A2 Dumbbell bench press')).toBeVisible();

  // first time: enter a weight, then log
  await page.getByRole('button', { name: 'Increase Set 1 weight' }).click();
  await page.getByRole('button', { name: 'Log set 1' }).first().click();
  await expect.poll(() => idbCount(page, 'sets')).toBe(1);

  // superset: moves to A2 automatically, rest timer shows
  await expect(page.getByRole('heading', { level: 1, name: 'Dumbbell bench press' })).toBeVisible();
  await expect(page.getByRole('timer', { name: 'Rest timer' })).toBeVisible();
  await page.getByRole('button', { name: 'Skip' }).click();
  await expect(page.getByRole('timer', { name: 'Rest timer' })).toHaveCount(0);

  // log A2 set 1 with the big bottom button → back to A1 set 2
  await page.getByRole('button', { name: 'Increase Set 1 weight' }).click();
  await page.getByRole('button', { name: /^Log set 1$/ }).last().click();
  await expect.poll(() => idbCount(page, 'sets')).toBe(2);
  await expect(page.getByRole('heading', { level: 1, name: 'Dumbbell goblet squat' })).toBeVisible();

  // kill the page mid-session → resume on the same exercise/set
  await page.reload();
  await expect(page.getByRole('heading', { level: 1, name: 'Dumbbell goblet squat' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Set 1 done, edit' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Log set 2' }).first()).toBeVisible();

  // minimise → resume bar on Today
  await page.getByRole('button', { name: 'Minimise workout' }).click();
  await expect(page.getByRole('link', { name: /Resume/ })).toBeVisible();
  await page.getByRole('link', { name: /Resume/ }).click();
  await expect(page).toHaveURL(/\/workout$/);
});

test('swap for today keeps separate history (swappedFrom recorded)', async ({ page }) => {
  await page.clock.install({ time: TUESDAY });
  await onboard(page);
  await startToday(page);
  await page.getByRole('button', { name: 'Next exercise' }).click();
  await page.getByRole('button', { name: /Busy\? → Dumbbell floor press/ }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Dumbbell floor press' })).toBeVisible();
  await page.getByRole('button', { name: 'Increase Set 1 weight' }).click();
  await page.getByRole('button', { name: 'Log set 1' }).first().click();
  const row = await page.evaluate(
    () =>
      new Promise<{ exerciseId: string; swappedFromExerciseId?: string }>((resolve) => {
        const req = indexedDB.open('repmate');
        req.onsuccess = () => {
          const all = req.result.transaction('sets').objectStore('sets').getAll();
          all.onsuccess = () => resolve(all.result[0]);
        };
      }),
  );
  expect(row.exerciseId).toBe('dumbbell-floor-press');
  expect(row.swappedFromExerciseId).toBe('dumbbell-bench-press');
});

test('alternates sheet: pick a research alternate for today', async ({ page }) => {
  await page.clock.install({ time: TUESDAY });
  await onboard(page);
  await startToday(page);
  await page.getByRole('button', { name: 'Alternates' }).click();
  const dialog = page.getByRole('dialog', { name: 'Alternates' });
  await dialog.getByRole('button', { name: /Bodyweight squat/ }).click();
  await dialog.getByRole('button', { name: 'Just today' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Bodyweight squat' })).toBeVisible();
  await expect(page.getByRole('button', { name: /Back to Dumbbell goblet squat/ })).toBeVisible();
});

test('express mode trims Strength A to the A/B lifts and finishing shows the summary + feedback', async ({ page }) => {
  await page.clock.install({ time: TUESDAY });
  await onboard(page);
  await page.getByRole('button', { name: /Start workout/ }).click();
  await page.getByRole('tab', { name: /Express/ }).click();
  await expect(page.getByText('4 exercises')).toBeVisible();
  await page.getByRole('button', { name: /Begin workout/ }).click();
  await page.getByRole('button', { name: 'Increase Set 1 weight' }).click();
  await page.getByRole('button', { name: 'Log set 1' }).first().click();
  await page.getByRole('button', { name: 'Workout menu' }).click();
  await page.getByRole('button', { name: 'Finish workout' }).click();
  await expect(page).toHaveURL(/\/workout\/summary\//);
  await page.getByRole('button', { name: /Too hard/ }).click();
  await page.getByRole('button', { name: 'Save & done' }).click();
  await expect(page).toHaveURL(/\/today/);
  await expect(page.getByRole('heading', { level: 2, name: /Strength A/ })).toBeVisible();
  await expect(page.getByText('Done today')).toBeVisible();
});
