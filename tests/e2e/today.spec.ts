import { test, expect } from '@playwright/test';
import { dismissIntro, onboard } from './helpers';

// Week of Mon 30 Nov 2026 (Dec 1 2026 is a Tuesday)
const at = (d: number, h = 8) => new Date(2026, 10, 30 + d, h, 0, 0);

test.describe('Today screen per weekday', () => {

  const cases: [number, RegExp][] = [
    [0, /Rest – gym closed/],
    [1, /Strength A/],
    [2, /Steady cardio/],
    [3, /Strength B/],
    [4, /Athletic power/],
    [5, /Strength C/],
    [6, /Active recovery/],
  ];
  for (const [d, title] of cases) {
    test(`day ${d} shows ${title}`, async ({ page }) => {
      await page.clock.install({ time: at(d) });
      await onboard(page);
      await expect(page.getByRole('heading', { level: 2, name: title })).toBeVisible();
    });
  }

  test('Tuesday hero has Start and the next meal card', async ({ page }) => {
    await page.clock.install({ time: at(1, 7) });
    await onboard(page);
    await expect(page.getByRole('button', { name: /Start workout/ })).toBeVisible();
    await expect(page.getByRole('article', { name: /Pre-gym at 08:30/ })).toBeVisible();
  });

  test('missed Tuesday → Wednesday becomes Strength A (auto re-plan)', async ({ page }) => {
    await page.clock.install({ time: at(0) });
    await onboard(page);
    await page.clock.setSystemTime(at(2));
    await page.reload();
    await dismissIntro(page);
    // Onboarded Monday, nothing done Tuesday → plan adjusted
    await expect(page.getByText('Plan adjusted for a missed session')).toBeVisible();
    await expect(page.getByRole('heading', { level: 2, name: /Strength A/ })).toBeVisible();
    await page.getByRole('button', { name: 'Keep original plan' }).click();
    await expect(page.getByRole('heading', { level: 2, name: /Steady cardio/ })).toBeVisible();
  });

  test('log weight from the quick-log row', async ({ page }) => {
    await onboard(page);
    await page.getByRole('button', { name: 'Log weight' }).click();
    await page.getByRole('button', { name: 'Decrease Body weight' }).click();
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText(/Weight logged · 79.9 kg/)).toBeVisible();
  });
});
