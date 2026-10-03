// The new tab's logic, kept free of the DOM and chrome.* so node --test can run it. Mirrors the terminal's voz.

const DAY_MS = 86_400_000;

// Day number since the epoch, in UTC, as the terminal's EPOCHSECONDS / 86400.
export function dayNumber(now = Date.now()) {
  return Math.floor(now / DAY_MS);
}

// Small seeded generator (mulberry32): the same seed gives the same sequence on every machine.
function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), a | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Category index (0..n-1) for a day: each shows once per n-day cycle, in an order shuffled per cycle.
// Same scheme as the terminal, but its own shuffle, so the two can be on different categories.
export function categoryIndex(n, day) {
  const rand = seeded(Math.floor(day / n));
  const order = Array.from({ length: n }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  return order[day % n];
}

// A phrase is keyed by its `phrase|translation` line, as in the terminal's learned file.
export const key = ([phrase, translation]) => `${phrase}|${translation}`;

// Pick from rows ([phrase, translation] pairs), skipping learned ones (a Set of keys) and the last one shown
// (a key), each only while something else is left. Order: unlearned and not last, any unlearned, any not
// last, any. Returns null when there are no rows.
export function pick(rows, learned, last, rand = Math.random) {
  const unlearned = rows.filter(r => !learned.has(key(r)));
  const notLast = r => key(r) !== last;
  const pool = [unlearned.filter(notLast), unlearned, rows.filter(notLast), rows].find(p => p.length);
  return pool ? pool[Math.floor(rand() * pool.length)] : null;
}

// Today's phrases for a region: its category for the day, plus the bot's phrases (which aren't a category).
export function todaysRows(region, mine, day) {
  const names = Object.keys(region).sort();
  if (!names.length) return { category: null, rows: mine };
  const category = names[categoryIndex(names.length, day)];
  return { category, rows: [...region[category], ...mine] };
}

// Control and format characters (bidi, zero-width, soft hyphen...), line and paragraph separators, or a |.
// The bot refuses the same set. It's a little wider than voz sync's byte list, which can't matter in practice.
const UNSAFE = /[|\p{Cc}\p{Cf}\u2028\u2029]/u;
const ROW = /^(\d+)\|([^|]+)\|([^|]+)$/;

// Every phrase already known for a region: all its categories, not just today's, plus the synced ones.
// Pass this to readSyncRows so a bot phrase that repeats a bundled one isn't added twice.
export function knownPhrases(region, mine) {
  return new Set([...Object.values(region).flat(), ...mine].map(([phrase]) => phrase));
}

// Read a /phrases response (bytes of `id|phrase|translation` lines) as `voz sync` does. Keeps well-formed
// rows of valid UTF-8 with nothing unsafe, whose phrase isn't already known (`have`, a Set of phrases, which
// this adds to). Returns the new [phrase, translation] rows and the highest id seen, to send as `since` next.
export function readSyncRows(bytes, have) {
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
  const rows = [];
  let maxId = 0;
  let start = 0;
  for (let i = 0; i <= bytes.length; i++) {
    if (i < bytes.length && bytes[i] !== 0x0a) continue;
    const lineBytes = bytes.subarray(start, i);
    start = i + 1;
    let digits = 0;
    while (lineBytes[digits] >= 0x30 && lineBytes[digits] <= 0x39) digits++;
    if (digits && lineBytes[digits] === 0x7c) maxId = Math.max(maxId, Number(String.fromCharCode(...lineBytes.subarray(0, digits))));
    let line;
    try { line = decoder.decode(lineBytes); } catch { continue; }
    const m = ROW.exec(line);
    if (!m || UNSAFE.test(m[2] + m[3]) || have.has(m[2])) continue;
    have.add(m[2]);
    rows.push([m[2], m[3]]);
  }
  return { rows, maxId };
}
