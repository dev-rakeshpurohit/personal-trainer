import { test, expect } from '@playwright/test';
import { KillableServer, waitForSW } from './helpers';

test('app shell is installable and loads with no network', async ({ page }) => {
  const server = new KillableServer(4181);
  await server.start();
  try {
    await page.goto(server.url + '/');
    const manifest = await page.request.get(server.url + '/manifest.webmanifest');
    expect(manifest.ok()).toBeTruthy();
    const json = await manifest.json();
    expect(json.display).toBe('standalone');
    expect(json.start_url).toBe('/?source=pwa');
    expect(json.icons.length).toBeGreaterThanOrEqual(3);
    await waitForSW(page);
    await server.stop();
    await page.goto(server.url + '/');
    await expect(page.locator('#root')).not.toBeEmpty();
  } finally {
    await server.stop();
  }
});
