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

// Today's phrases first. When none of them is both unlearned and different from the last one shown, an unlearned
// phrase from anywhere in the region (`everything`), so learned phrases come back, and the last one repeats,
// only once nothing else is left.
export function pickPhrase(today, everything, learned, last, rand = Math.random) {
  const unlearned = rows => rows.filter(r => !learned.has(key(r)));
  const fresh = rows => unlearned(rows).filter(r => key(r) !== last);
  const pool = fresh(today).length ? today : [fresh(everything), unlearned(everything)].find(p => p.length) ?? today;
  return pick(pool, learned, last, rand);
}

// Today's phrases for a region: its category for the day, plus the bot's phrases (which aren't a category).
export function todaysRows(region, mine, day) {
  const names = Object.keys(region).sort();
  if (!names.length) return { category: null, rows: mine };
  const category = names[categoryIndex(names.length, day)];
  return { category, rows: [...region[category], ...mine] };
}

const DEFAULTS = { region: 'es_AR', delay: 2, learned: [], last: null, mine: [], swapped: false, pending: [], linked: false };
const isText = v => typeof v === 'string' && v !== '';

// Stored settings with anything malformed replaced by its default, so a bad value (a sync gone wrong, an old
// version's data) can't break the page. mine keeps only [phrase, meaning] pairs of non-empty strings.
export function cleanSettings(stored = {}) {
  const s = stored ?? {};
  return {
    region: isText(s.region) ? s.region : DEFAULTS.region,
    delay: Number.isInteger(s.delay) && s.delay >= 0 && s.delay <= 30 ? s.delay : DEFAULTS.delay,
    learned: Array.isArray(s.learned) ? s.learned.filter(isText) : [],
    last: isText(s.last) ? s.last : null,
    mine: Array.isArray(s.mine) ? s.mine.filter(r => Array.isArray(r) && r.length === 2 && r.every(isText)) : [],
    swapped: s.swapped === true,
    pending: Array.isArray(s.pending)
      ? s.pending.filter(p => isText(p?.key) && typeof p.on === 'boolean' && Number.isFinite(p.at)) : [],
    linked: s.linked === true,
  };
}

// Marks made while the terminal's host couldn't be reached wait in `pending`, oldest first. Only the latest mark
// for a phrase matters, so a new one replaces any earlier one for the same phrase.
export function queueMark(pending, key, on, at) {
  return [...pending.filter(p => p.key !== key), { key, on, at }];
}

// What's left of `pending` once the marks in `sent` have reached the terminal. Marks queued since stay.
export function withoutSent(pending, sent) {
  const done = new Set(sent.map(p => `${p.at} ${p.on} ${p.key}`));
  return pending.filter(p => !done.has(`${p.at} ${p.on} ${p.key}`));
}

// The terminal's host (vozlocal-host) sends phrases as hex of their UTF-8 bytes, so it never escapes JSON.
export const toHex = text => Array.from(new TextEncoder().encode(text), b => b.toString(16).padStart(2, '0')).join('');

export function fromHex(hex) {
  if (typeof hex !== 'string' || !/^(?:[0-9a-f]{2})+$/.test(hex)) throw new Error('not hex');
  return new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(hex.match(/../g), h => parseInt(h, 16)));
}

// The learned keys and mine.psv rows in a host reply, or null if it isn't a good one. Lines that don't decode,
// or that hold anything unsafe, are dropped, as voz sync drops them.
export function readHostReply(reply) {
  if (reply?.ok !== true || !Array.isArray(reply.learned) || !Array.isArray(reply.mine)) return null;
  const lines = list => list.flatMap(hex => {
    try {
      const line = fromHex(hex);
      return /[\p{Cc}\p{Cf}\u2028\u2029]/u.test(line) || !line.includes('|') ? [] : [line];
    } catch { return []; }
  });
  const mine = lines(reply.mine).map(line => {
    const at = line.indexOf('|');
    return [line.slice(0, at), line.slice(at + 1)];
  }).filter(([phrase, meaning]) => phrase && meaning && !meaning.includes('|'));
  return { learned: lines(reply.learned), mine };
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
    if (digits && lineBytes[digits] === 0x7c) maxId = Math.max(maxId, Number(decoder.decode(lineBytes.subarray(0, digits))));
    let line;
    try { line = decoder.decode(lineBytes); } catch { continue; }
    const m = ROW.exec(line);
    if (!m || UNSAFE.test(m[2] + m[3]) || have.has(m[2])) continue;
    have.add(m[2]);
    rows.push([m[2], m[3]]);
  }
  return { rows, maxId };
}
