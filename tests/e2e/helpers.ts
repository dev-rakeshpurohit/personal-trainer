import { spawn, type ChildProcess } from 'node:child_process';
import { expect, type Page } from '@playwright/test';

/**
 * Playwright's WebKit `context.setOffline(true)` blocks requests *before* the service worker sees them,
 * so it can't exercise the SW. Instead we run a private preview server and kill it: a real network failure,
 * like airplane mode, where only the service worker + IndexedDB can answer.
 */
export class KillableServer {
  proc?: ChildProcess;
  constructor(public port: number) {}
  get url() {
    return `http://localhost:${this.port}`;
  }
  async start() {
    this.proc = spawn('pnpm', ['exec', 'vite', 'preview', '--port', String(this.port), '--strictPort'], {
      stdio: 'ignore',
      detached: true,
    });
    for (let i = 0; i < 100; i++) {
      try {
        const r = await fetch(this.url);
        if (r.ok) return;
      } catch {
        /* not up yet */
      }
      await new Promise((r) => setTimeout(r, 150));
    }
    throw new Error('preview server did not start');
  }
  async stop() {
    if (!this.proc?.pid) return;
    try {
      process.kill(-this.proc.pid, 'SIGKILL');
    } catch {
      /* already gone */
    }
    for (let i = 0; i < 50; i++) {
      try {
        await fetch(this.url);
      } catch {
        return;
      }
      await new Promise((r) => setTimeout(r, 100));
    }
  }
}

export async function waitForSW(page: Page) {
  await page.waitForFunction(async () => (await navigator.serviceWorker.getRegistration())?.active?.state === 'activated');
  await page.reload();
  await page.waitForFunction(() => !!navigator.serviceWorker.controller);
  // let the precache finish populating
  await page.waitForFunction(async () => {
    const keys = await caches.keys();
    if (!keys.length) return false;
    const c = await caches.open(keys[0]);
    return (await c.keys()).length > 20;
  });
}

export async function expectNoServer(url: string) {
  await expect(fetch(url)).rejects.toThrow();
}

/** Complete onboarding with the ready-made template (defaults). */
export async function onboard(page: Page, opts: { name?: string } = {}) {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /Your coach/ })).toBeVisible();
  await page.getByRole('button', { name: 'Get started' }).click();
  await page.getByPlaceholder('What should we call you?').fill(opts.name ?? 'Alex');
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: "Let's train" }).click();
  await expect(page).toHaveURL(/\/today/);
}

/** Count rows in an IndexedDB table via Dexie's raw IDB. */
export async function idbCount(page: Page, table: string): Promise<number> {
  return page.evaluate(
    (t) =>
      new Promise<number>((resolve, reject) => {
        const req = indexedDB.open('repmate');
        req.onsuccess = () => {
          const tx = req.result.transaction(t, 'readonly');
          const c = tx.objectStore(t).count();
          c.onsuccess = () => {
            resolve(c.result);
            req.result.close();
          };
          c.onerror = () => reject(c.error);
        };
        req.onerror = () => reject(req.error);
      }),
    table,
  );
}
