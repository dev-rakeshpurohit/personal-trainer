# Repmate — personal trainer PWA

Spec-first repo. **Claude Code: start with `CLAUDE.md`.**

- `CLAUDE.md`: instructions, non-negotiables, stack, commands
- `docs/01–08`: PRD, UX, architecture, data model, offline/media, logic rules, build plan, deployment
- `seed/`: the Lean & Athletic program, the veg + egg 2,000 kcal diet, and the exercise-image id list

## Before you start (one time, 2 minutes)
1. In the VS Code terminal: `pnpm dlx vercel@latest login` (finish it in the browser).
2. In Claude Code, set the permission mode you're comfortable with (e.g. Shift+Tab → "accept edits on", and allow `pnpm`, `git` and `vercel` commands when it first asks) so the build doesn't stall waiting for approval.

## Kick-off prompt for Claude in VS Code
> Read CLAUDE.md, every file in docs/ and seed/. Build Repmate completely end to end in autonomous mode: run milestones M0 to M8 from docs/07-BUILD-PLAN.md back to back without asking me anything. Where something is unclear, choose the sensible default, log it in docs/DECISIONS.md and continue. Commit after each milestone, and fix all failing lint, type, unit and Playwright (including offline) tests before moving on. When everything is done, deploy to production on my Vercel account as project `repmate-test` (`vercel deploy --prod --yes`), verify the live URL, sw.js and manifest headers. Optimise only for my iPhone 13 as a Home Screen app (see the iPhone section in CLAUDE.md), write HANDOFF.md, and end with the production URL as your final message. Don't stop for approvals. The only exception: if Vercel isn't logged in, finish building first and then ask me once.
