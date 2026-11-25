/* Generates the app icon set and the iPhone 13 splash screen from an SVG mark. */
import sharp from 'sharp';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..', 'public');
mkdirSync(path.join(root, 'icons'), { recursive: true });
mkdirSync(path.join(root, 'splash'), { recursive: true });

const mark = (size: number, pad: number, rounded: boolean) => {
  const inner = size - pad * 2;
  const r = rounded ? size * 0.22 : 0;
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FF9A3D"/><stop offset="1" stop-color="#FF5E0E"/>
    </linearGradient>
  </defs>
  <rect width="${size}" height="${size}" rx="${r}" fill="#0B0F14"/>
  <g transform="translate(${pad} ${pad}) scale(${inner / 100})">
    <rect x="8" y="8" width="84" height="84" rx="22" fill="url(#g)"/>
    <path d="M34 74V26h17c11 0 18 6 18 15 0 7-4 12-10 14l12 19H58L48 57h-3v17H34zm11-27h6c4 0 7-2 7-6s-3-6-7-6h-6v12z" fill="#0B0F14"/>
  </g>
</svg>`);
};

const out = async (svg: Buffer, size: number, file: string) =>
  sharp(svg).resize(size, size).png({ compressionLevel: 9 }).toFile(path.join(root, file));

await out(mark(512, 40, true), 192, 'icons/icon-192.png');
await out(mark(512, 40, true), 512, 'icons/icon-512.png');
await out(mark(512, 96, false), 512, 'icons/maskable-512.png');
await out(mark(512, 0, false), 180, 'icons/apple-touch-icon-180.png');
await out(mark(512, 40, true), 32, 'icons/favicon-32.png');

// iPhone 13 portrait splash 1170x2532
const W = 1170, H = 2532, L = 300;
const logo = await sharp(mark(512, 0, true)).resize(L, L).png().toBuffer();
const text = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="200">
  <text x="50%" y="120" text-anchor="middle" font-family="Helvetica Neue, Arial" font-weight="700" font-size="88" fill="#F2F5F8">Repmate</text></svg>`);
await sharp({ create: { width: W, height: H, channels: 4, background: '#0B0F14' } })
  .composite([
    { input: logo, top: Math.round(H / 2 - L / 2 - 80), left: Math.round(W / 2 - L / 2) },
    { input: text, top: Math.round(H / 2 + L / 2 - 40), left: 0 },
  ])
  .png({ compressionLevel: 9 })
  .toFile(path.join(root, 'splash/iphone13-1170x2532.png'));
console.log('icons + splash generated');
