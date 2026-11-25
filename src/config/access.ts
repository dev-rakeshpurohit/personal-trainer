/**
 * Invite gate. Only a salted SHA-256 hash of the access code ships in the bundle; the code itself is
 * never committed (it lives in the owner's notes / .access-code.local, which is git-ignored).
 * To rotate: run `pnpm gen:code`, then redeploy.
 * Note: with no server this keeps casual visitors out, it is not strong security. All data stays on-device anyway.
 */
export const ACCESS_SALT = 'e5dc3928bcd9c68c8a8fd7b92b9703a0';
export const ACCESS_HASH = '41d9237e71978abe0ad4fdfbcb91484a052dcc4fbc21b3aa374e1ea77b673a7b';
