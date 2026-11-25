/** Rotates the invite code: writes a new salted hash to src/config/access.ts and the code to .access-code.local. */
import { createHash, randomBytes, randomInt } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import path from 'node:path';

const A = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const part = () => Array.from({ length: 4 }, () => A[randomInt(A.length)]).join('');
const code = `RPM-${part()}-${part()}`;
const salt = randomBytes(16).toString('hex');
const hash = createHash('sha256').update(salt + code).digest('hex');
const root = path.resolve(import.meta.dirname, '..');
writeFileSync(path.join(root, '.access-code.local'), `${code}\n`);
writeFileSync(
  path.join(root, 'src/config/access.ts'),
  `/**
 * Invite gate. Only a salted SHA-256 hash of the access code ships in the bundle; the code itself is
 * never committed (it lives in the owner's notes / .access-code.local, which is git-ignored).
 * To rotate: run \`pnpm gen:code\`, then redeploy.
 * Note: with no server this keeps casual visitors out, it is not strong security. All data stays on-device anyway.
 */
export const ACCESS_SALT = '${salt}';
export const ACCESS_HASH = '${hash}';
`,
);
console.log(`New access code written to .access-code.local (not committed).`);
