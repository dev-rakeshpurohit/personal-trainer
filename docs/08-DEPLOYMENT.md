# 08 — Deployment (Vercel)

## Project
- Vercel project name: **`repmate-test`** (Rakesh's personal Vercel account / personal scope, not a client team).
- Framework preset: Vite. Build: `pnpm build`. Output: `dist`. Node 20.
- No environment variables are needed in v1.

## Deploy (autonomous: no approval step)
Rakesh logs in to the Vercel CLI once **before** the build starts (`pnpm dlx vercel@latest login`). Use that session, or `VERCEL_TOKEN` if it's set.
```bash
pnpm dlx vercel@latest whoami                                   # confirm auth; if it fails, see CLAUDE.md
pnpm dlx vercel@latest link --yes --project repmate-test        # personal scope; creates the project if missing
pnpm dlx vercel@latest deploy --yes                             # optional preview after milestones
pnpm dlx vercel@latest deploy --prod --yes                      # final production deploy after M8
```
After the prod deploy, verify:
```bash
curl -sI https://<prod-url>/ | head -1                          # 200
curl -sI https://<prod-url>/sw.js | grep -i cache-control       # no-cache
curl -sI https://<prod-url>/manifest.webmanifest | grep -i content-type
```
Keep Deployment Protection **off** for production so the PWA can be installed on his phone.

## HANDOFF.md (write this last, in the repo root)
- **Live URL** (production) on the first line
- How to install: iPhone (Safari → Share → Add to Home Screen) / Android (Chrome → Install app)
- First-run steps: open once online → finish onboarding → pick "Lean & Athletic" + "Veg + eggs 2,000 kcal"
- "Test on your phone" checklist (doc 07, manual test list)
- What was built (milestones ✓), known limitations, and the decisions summary (link to DECISIONS.md)
- How to redeploy later: `pnpm dlx vercel@latest deploy --prod --yes`

## vercel.json
```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "buildCommand": "pnpm build",
  "outputDirectory": "dist",
  "rewrites": [{ "source": "/((?!assets|media|icons|fonts|sw.js|manifest.webmanifest).*)", "destination": "/index.html" }],
  "headers": [
    { "source": "/sw.js", "headers": [
      { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" },
      { "key": "Service-Worker-Allowed", "value": "/" } ] },
    { "source": "/manifest.webmanifest", "headers": [
      { "key": "Content-Type", "value": "application/manifest+json" },
      { "key": "Cache-Control", "value": "no-cache" } ] },
    { "source": "/assets/(.*)", "headers": [
      { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" } ] },
    { "source": "/media/(.*)", "headers": [
      { "key": "Cache-Control", "value": "public, max-age=2592000" } ] },
    { "source": "/(.*)", "headers": [
      { "key": "X-Content-Type-Options", "value": "nosniff" },
      { "key": "Referrer-Policy", "value": "no-referrer" },
      { "key": "Permissions-Policy", "value": "camera=(self), microphone=(), geolocation=()" },
      { "key": "Content-Security-Policy", "value": "default-src 'self'; img-src 'self' blob: data:; media-src 'self' blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; font-src 'self'; connect-src 'self'; worker-src 'self'; manifest-src 'self'; frame-ancestors 'none'" } ] }
  ]
}
```
(YouTube opens as a normal external link, so it doesn't need a CSP entry.)

## Manifest essentials
`name: "Repmate"`, `short_name: "Repmate"`, `start_url: "/?source=pwa"`, `display: "standalone"`, `orientation: "portrait"`, `background_color: "#0B0F14"`, `theme_color: "#0B0F14"`, icons 192/512 plus maskable 512, plus `apple-touch-icon` 180 and `apple-mobile-web-app-capable` meta tags in index.html. Add shortcuts: "Start today's workout" → `/workout/today`, "Log weight" → `/today?log=weight`.

## Privacy on a public URL
The URL is public, but the app holds no data. Everything stays on each visitor's device. Production stays unprotected so it can be installed as a PWA.

## Release checklist (Claude runs it all)
- [ ] All tests green incl. Playwright offline spec; Lighthouse targets met (doc 07 M8)
- [ ] `vercel deploy --prod --yes`
- [ ] Header checks above pass on the prod URL
- [ ] HANDOFF.md written; final message = production URL
