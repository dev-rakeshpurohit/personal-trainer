/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import path from 'node:path';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')) as { version: string };

/**
 * Offline media budget: precache every demo thumbnail, the animations of the curated plan exercises,
 * and the fallback photos only for exercises without a 3D demo. The other ~1,100 animations are cached
 * on first view (or via Settings → Storage → Download all demos).
 */
function mediaPrecache(): { url: string; revision: string }[] {
  const rev = (f: string) => createHash('md5').update(readFileSync(f)).digest('hex').slice(0, 12);
  const out: { url: string; revision: string }[] = [];
  const demoMap = JSON.parse(readFileSync('seed/demo-map.json', 'utf8')) as { map: Record<string, string | null> };
  const curated = new Set(Object.values(demoMap.map).filter(Boolean) as string[]);
  const demos = 'public/media/demos';
  if (existsSync(demos))
    for (const f of readdirSync(demos)) {
      const id = f.replace(/(-t)?\.webp$/, '');
      if (f.endsWith('-t.webp') || curated.has(id)) out.push({ url: `/media/demos/${f}`, revision: rev(`${demos}/${f}`) });
    }
  // fallback photos only for exercises without a 3D demo (all of them if demos weren't fetched in this checkout)
  const haveDemos = existsSync(demos) && readdirSync(demos).length > 0;
  const photoIds = haveDemos
    ? (JSON.parse(readFileSync('seed/demo-map.json', 'utf8')) as { fallbackPhotos: string[] }).fallbackPhotos
    : readdirSync('public/media/exercises').filter((f) => !f.includes('.'));
  for (const id of photoIds) {
    const dir = `public/media/exercises/${id}`;
    if (existsSync(dir)) for (const f of readdirSync(dir)) out.push({ url: `/media/exercises/${id}/${f}`, revision: rev(`${dir}/${f}`) });
  }
  return out;
}

export default defineConfig({
  resolve: { alias: { '@': path.resolve(__dirname, 'src') } },
  define: { __APP_VERSION__: JSON.stringify(`${pkg.version}`) },
  build: { target: 'es2021', sourcemap: false, chunkSizeWarningLimit: 600 },
  plugins: [
    react(),
    VitePWA({
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      registerType: 'prompt',
      injectRegister: null,
      manifestFilename: 'manifest.webmanifest',
      includeAssets: ['icons/*.png', 'splash/*.png', 'wake.mp4'],
      injectManifest: {
        globPatterns: ['**/*.{js,css,html,woff2,png,svg,webp,json,mp4}'],
        globIgnores: ['media/demos/**', 'media/exercises/**'],
        additionalManifestEntries: mediaPrecache(),
        maximumFileSizeToCacheInBytes: 3 * 1024 * 1024,
      },
      manifest: {
        id: '/',
        name: 'Repmate',
        short_name: 'Repmate',
        description: 'Your offline gym coach and food diary.',
        start_url: '/?source=pwa',
        scope: '/',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#0B0F14',
        theme_color: '#0B0F14',
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
        shortcuts: [
          { name: "Start today's workout", short_name: 'Workout', url: '/workout/today' },
          { name: 'Log weight', short_name: 'Weight', url: '/today?log=weight' },
        ],
      },
      devOptions: { enabled: false },
    }),
  ],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
    include: ['src/**/*.test.{ts,tsx}', 'api/**/*.test.ts'],
    passWithNoTests: true,
  },
});
