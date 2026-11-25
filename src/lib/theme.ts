export type Theme = 'dark' | 'light' | 'system';

export function applyTheme(theme: Theme | undefined) {
  const t = theme ?? 'dark';
  const dark = t === 'dark' || (t === 'system' && !window.matchMedia('(prefers-color-scheme: light)').matches);
  const root = document.documentElement;
  root.classList.toggle('dark', dark);
  root.classList.toggle('light', !dark);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#0B0F14' : '#F5F6F8');
  try {
    localStorage.setItem('repmate:theme', t);
  } catch {
    /* private mode */
  }
}

export function applyStoredTheme() {
  try {
    applyTheme((localStorage.getItem('repmate:theme') as Theme) ?? 'dark');
  } catch {
    applyTheme('dark');
  }
}
