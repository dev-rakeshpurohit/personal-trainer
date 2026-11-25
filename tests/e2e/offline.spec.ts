import { test, expect } from '@playwright/test';
import { KillableServer, onboard, waitForSW } from './helpers';

test('airplane mode: open app, run a full Strength A session, finish with summary', async ({ page }) => {
  test.setTimeout(120_000);
  await page.clock.install({ time: new Date(2026, 11, 1, 9, 15) });
  const server = new KillableServer(4183);
  await server.start();
  try {
    await page.goto(server.url + '/');
    await waitForSW(page);
    await onboard(page, { base: server.url });

    // ✈️ network gone
    await server.stop();
    await page.goto(server.url + '/today');
    await expect(page.getByRole('heading', { level: 2, name: /Strength A/ })).toBeVisible();
    await page.getByRole('button', { name: /Start workout/ }).click();
    await page.getByRole('button', { name: /Begin workout/ }).click();

    // demo image served offline by the SW
    const img = page.locator('img[src*="Goblet_Squat/0.webp"]').first();
    await expect(img).toBeVisible();
    expect(await img.evaluate((el: HTMLImageElement) => el.naturalWidth > 0)).toBe(true);

    const finish = page.getByRole('button', { name: 'Finish workout' });
    for (let i = 0; i < 40 && !(await finish.isVisible()); i++) {
      const skip = page.getByRole('button', { name: /^(Skip|Done)$/ });
      if (await skip.isVisible()) await skip.click();
      const log = page.locator('footer').getByRole('button', { name: /^Log set \d+$/ });
      if (await log.isVisible()) await log.click();
      else {
        const done = page.locator('footer').getByRole('button', { name: 'Exercise done' });
        if (await done.isVisible()) await done.click();
      }
    }
    await expect(finish).toBeVisible();
    await finish.click();
    await expect(page).toHaveURL(/summary/);
    await expect(page.getByText('Sets', { exact: true })).toBeVisible();
    await expect(page.locator('p.tnum', { hasText: /^19$/ })).toBeVisible();
  } finally {
    await server.stop();
  }
});
