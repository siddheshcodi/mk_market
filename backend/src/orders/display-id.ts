import { randomInt } from 'crypto';

// No 0/O or 1/I, so the ID is easy to read out over the phone.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

/** e.g. MK261008A3F9K2: "MK" + order date in IST (YYMMDD) + 6 random characters (spec §6.6). */
export function newDisplayOrderId(at: Date): string {
  const ist = new Date(at.getTime() + IST_OFFSET_MS).toISOString();
  const date = ist.slice(2, 4) + ist.slice(5, 7) + ist.slice(8, 10);
  let suffix = '';
  for (let i = 0; i < 6; i++) suffix += ALPHABET[randomInt(ALPHABET.length)];
  return `MK${date}${suffix}`;
}
