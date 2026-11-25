import { test, expect } from '@playwright/test';
import { KillableServer, onboard, waitForSW } from './helpers';

test('library and exercise detail work with no network', async ({ page }) => {
  const server = new KillableServer(4182);
  await server.start();
  try {
    await page.goto(server.url + '/');
    await waitForSW(page);
    await onboard(page, { base: server.url });
    await server.stop();

    await page.goto(server.url + '/train/library');
    await page.getByPlaceholder('Search exercises').fill('goblet');
    await page.getByRole('link', { name: /Dumbbell goblet squat/ }).click();
    await expect(page.getByRole('heading', { name: 'Dumbbell goblet squat' })).toBeVisible();
    const img = page.locator('img[src*="Goblet_Squat/0.webp"]');
    await expect(img).toBeVisible();
    const loaded = await img.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth > 0);
    expect(loaded).toBe(true);
    // YouTube is online-only: the chip still shows because navigator.onLine is true with a dead server,
    // so we only assert the offline demo renders.
  } finally {
    await server.stop();
  }
});

test('train tab lists the week and opens a day', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 1, 8) });
  await onboard(page);
  await page.getByRole('link', { name: 'Train' }).click();
  await page.getByRole('button', { name: /Strength B – full body/ }).first().click();
  await expect(page.getByRole('dialog')).toContainText('Leg press');
  await expect(page.getByRole('button', { name: /Start this session/ })).toBeVisible();
});
