// The screensaver's pure logic, free of the DOM so node --test can run it.

export const CACHE_KEY = 'vozlocal.personal';
export const DIM_MINUTES = 30; // how long the text takes to fade to its dimmest
export const DIM_MIN = 0.35;   // the dimmest opacity: still readable, but not a fixed bright image on an OLED
export const DRIFT_RANGE = 10; // the text wanders up to this many vw/vh from the centre

// The Worker's GET /phrases body: `id|phrase|translation` lines. Anything else is dropped, as the terminal's
// sync does: the text is shown on a screen, so no control or hidden characters.
export function parsePersonal(text) {
  return String(text ?? '').split('\n').flatMap(line => {
    const [id, phrase, translation, ...extra] = line.split('|');
    const ok = /^\d+$/.test(id) && phrase && translation && !extra.length && !/[\p{Cc}\p{Cf}\u2028\u2029]/u.test(line);
    return ok ? [[phrase.trim(), translation.trim()]] : [];
  }).filter(([phrase, translation]) => phrase && translation);
}

// A random spot near the centre, as vw and vh offsets. Moving the text now and then spreads the wear on the screen.
export function driftOffset(rand = Math.random) {
  const spot = () => Math.round((rand() * 2 - 1) * DRIFT_RANGE);
  return { x: spot(), y: spot() };
}

// Opacity after the screensaver has run for `minutes`: 1 at the start, falling in a straight line to DIM_MIN.
export function dimAt(minutes) {
  return Math.max(DIM_MIN, Math.min(1, 1 - (minutes / DIM_MINUTES) * (1 - DIM_MIN)));
}

// The last phrases fetched, kept in localStorage so the screensaver works offline. Storage can be missing or
// full, so a failure is an empty list or a skipped write, never a crash.
export function readCache(storage) {
  try {
    const rows = JSON.parse(storage.getItem(CACHE_KEY));
    return Array.isArray(rows) ? rows.filter(r => Array.isArray(r) && r.length === 2 && r.every(s => typeof s === 'string' && s)) : [];
  } catch { return []; }
}

export function writeCache(storage, rows) {
  try { storage.setItem(CACHE_KEY, JSON.stringify(rows)); } catch { /* the next fetch tries again */ }
}
