import { test, type Page } from '@playwright/test';
import { ACCESS_CODE, dismissIntro, onboard } from './helpers';

const DIR = process.env.SHOTS_DIR ?? 'test-results/shots';
const shot = async (page: Page, name: string, full = false) => {
  await page.waitForTimeout(450);
  await page.screenshot({ path: `${DIR}/${name}.png`, fullPage: full });
};

test.describe('screenshots (on demand)', () => {
  test.skip(!process.env.SHOTS_DIR, 'set SHOTS_DIR to capture');
  test.setTimeout(180_000);

  test('onboarding journey', async ({ page }) => {
    await page.goto('/');
    await shot(page, '01-gate');
    await page.getByPlaceholder('RPM-XXXX-XXXX').fill(ACCESS_CODE);
    await page.getByRole('button', { name: 'Unlock' }).click();
    await shot(page, '02-welcome');
    await page.getByRole('button', { name: 'Get started' }).click();
    await shot(page, '03-goal', true);
    await page.getByRole('button', { name: 'Continue' }).click();
    await page.getByPlaceholder('What should we call you?').fill('Rakesh');
    await shot(page, '04-about', true);
    await page.getByRole('button', { name: 'Continue' }).click();
    await shot(page, '05-schedule', true);
    await page.getByRole('button', { name: 'Continue' }).click();
    await shot(page, '06-equipment', true);
    await page.getByRole('button', { name: 'Continue' }).click();
    await shot(page, '07-food', true);
    await page.getByRole('button', { name: 'Continue' }).click();
    await shot(page, '08-review', true);
  });

  test('app screens with demo data', async ({ page }) => {
    await page.clock.install({ time: new Date(2026, 11, 22, 7, 45) }); // Tuesday morning
    await onboard(page, { name: 'Rakesh' });
    await page.goto('/more/dev');
    await page.getByRole('button', { name: 'Load 30 days of demo data' }).click();
    await page.waitForURL(/progress/);
    await shot(page, '20-progress-body', true);
    await page.getByRole('tab', { name: 'Strength' }).click();
    await shot(page, '21-progress-strength', true);
    await page.getByRole('tab', { name: 'Consistency' }).click();
    await shot(page, '22-progress-consistency', true);
    await page.goto('/today');
    await dismissIntro(page);
    await shot(page, '10-today');
    await shot(page, '11-today-full', true);
    await page.goto('/train');
    await shot(page, '12-train', true);
    await page.goto('/train/library');
    await shot(page, '13-library');
    await page.goto('/train/library/dumbbell-goblet-squat');
    await shot(page, '14-exercise', true);
    await page.goto('/eat');
    await shot(page, '15-eat');
    await page.goto('/train/history');
    await shot(page, '16-history');
    await page.goto('/more');
    await shot(page, '17-more');
    await page.goto('/more/setup');
    await shot(page, '18-setup');
    await page.goto('/more/settings');
    await shot(page, '19-settings', true);
    await page.goto('/more/plan');
    await page.getByRole('link', { name: /Strength A/ }).click();
    await shot(page, '23-day-editor', true);

    await page.goto('/today');
    await page.getByRole('button', { name: /Start workout/ }).click();
    await shot(page, '30-prestart', true);
    await page.getByRole('button', { name: /Begin workout/ }).click();
    await shot(page, '31-player');
    await page.getByRole('button', { name: 'Log set 1' }).first().click();
    await shot(page, '32-player-rest');
    await page.getByRole('button', { name: 'Skip' }).click();
    await page.getByRole('button', { name: 'Alternates' }).click();
    await shot(page, '33-alternates');
    await page.keyboard.press('Escape');
    await page.getByRole('button', { name: 'Workout menu' }).click();
    await page.getByRole('button', { name: 'Finish workout' }).click();
    await shot(page, '34-summary', true);
  });

  test('light theme sample', async ({ page }) => {
    await page.clock.install({ time: new Date(2026, 11, 22, 7, 45) });
    await onboard(page, { name: 'Rakesh' });
    await page.goto('/more/settings');
    await page.getByRole('tab', { name: 'Light' }).click();
    await page.goto('/today');
    await shot(page, '40-today-light');
    await page.goto('/eat');
    await shot(page, '41-eat-light');
  });
});
