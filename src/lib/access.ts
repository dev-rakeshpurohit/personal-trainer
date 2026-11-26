import { ACCESS_HASH, ACCESS_SALT } from '@/config/access';

const KEY = 'repmate:unlocked';

export const normaliseCode = (c: string) =>
  c
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .replace(/^RPM(.{4})(.{4})$/, 'RPM-$1-$2');

export async function hashCode(code: string): Promise<string> {
  const data = new TextEncoder().encode(ACCESS_SALT + normaliseCode(code));
  const buf = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function checkCode(code: string): Promise<boolean> {
  try {
    return (await hashCode(code)) === ACCESS_HASH;
  } catch {
    return false;
  }
}

export function isUnlocked(): boolean {
  try {
    return localStorage.getItem(KEY) === ACCESS_HASH.slice(0, 16);
  } catch {
    return false;
  }
}

const CODE_KEY = 'repmate:code';

/** The invite code itself is kept on this device so the AI coach can prove access to the server. */
export function storedCode(): string | undefined {
  try {
    return localStorage.getItem(CODE_KEY) ?? undefined;
  } catch {
    return undefined;
  }
}
export function storeCode(code: string) {
  try {
    localStorage.setItem(CODE_KEY, normaliseCode(code));
  } catch {
    /* private mode */
  }
}

export function markUnlocked(code?: string) {
  if (code) storeCode(code);
  try {
    localStorage.setItem(KEY, ACCESS_HASH.slice(0, 16));
  } catch {
    /* private mode: the gate shows again next time */
  }
}
