import { test } from '@playwright/test';
import { onboard } from './helpers';
const DIR = process.env.SHOTS_DIR ?? 'test-results/shots';

test('screenshots: progress', async ({ page }) => {
  test.skip(!process.env.SHOTS_DIR, 'screenshots only on demand');
  await page.clock.install({ time: new Date(2026, 11, 20, 8, 0) });
  await onboard(page);
  await page.goto('/more/dev');
  await page.getByRole('button', { name: 'Load 30 days of demo data' }).click();
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${DIR}/progress-body.png`, fullPage: true });
  await page.getByRole('tab', { name: 'Strength' }).click();
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${DIR}/progress-strength.png`, fullPage: true });
  await page.getByRole('tab', { name: 'Consistency' }).click();
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${DIR}/progress-consistency.png`, fullPage: true });
});
