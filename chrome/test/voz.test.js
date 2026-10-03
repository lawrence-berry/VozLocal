import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { categoryIndex, cleanSettings, dayNumber, fromHex, key, knownPhrases, readHostReply, toHex, pick, readSyncRows, todaysRows } from '../extension/lib/voz.js';

const bytes = s => new TextEncoder().encode(s);
const phrases = JSON.parse(readFileSync(new URL('../extension/data/phrases.json', import.meta.url), 'utf8'));

test('dayNumber counts UTC days since the epoch', () => {
  assert.equal(dayNumber(0), 0);
  assert.equal(dayNumber(Date.UTC(2026, 9, 3, 23, 59)), 20729);
  assert.equal(dayNumber(Date.UTC(2026, 9, 4, 0, 0)), 20730);
});

test('categoryIndex shows every category once per cycle', () => {
  for (const n of [1, 2, 5, 7]) {
    for (const cycle of [0, 1, 2913]) {
      const seen = Array.from({ length: n }, (_, pos) => categoryIndex(n, cycle * n + pos));
      assert.deepEqual([...seen].sort(), Array.from({ length: n }, (_, i) => i), `n=${n} cycle=${cycle}`);
    }
  }
});

test('categoryIndex is the same on every run and shuffles between cycles', () => {
  const cycle = c => Array.from({ length: 5 }, (_, pos) => categoryIndex(5, c * 5 + pos)).join('');
  assert.equal(cycle(4073), cycle(4073));
  assert.ok(new Set(Array.from({ length: 20 }, (_, c) => cycle(c))).size > 1);
});

const rows = [['uno', 'one'], ['dos', 'two'], ['tres', 'three']];
// Every phrase pick can return, found by sweeping rand() across [0, 1).
const pool = (...args) => new Set(Array.from({ length: 12 }, (_, i) => pick(...args, () => i / 12)?.[0]));

test('pick skips learned phrases and the last one shown', () => {
  assert.deepEqual(pool(rows, new Set([key(rows[0])]), key(rows[1])), new Set(['tres']));
  assert.deepEqual(pool(rows, new Set(), key(rows[1])), new Set(['uno', 'tres']));
});

test('pick falls back: any unlearned, then any not last, then any', () => {
  // Only "dos" is unlearned, and it was shown last: an unlearned repeat beats a learned phrase.
  assert.deepEqual(pick(rows, new Set([key(rows[0]), key(rows[2])]), key(rows[1])), rows[1]);
  // All learned: anything but the last.
  assert.deepEqual(pool(rows, new Set(rows.map(key)), key(rows[0])), new Set(['dos', 'tres']));
  // A category's only phrase shows every time.
  assert.deepEqual(pick([rows[0]], new Set(), key(rows[0])), rows[0]);
  assert.equal(pick([], new Set(), null), null);
});

test('pick can return any phrase when nothing is learned or shown', () => {
  assert.deepEqual(pool(rows, new Set(), null), new Set(['uno', 'dos', 'tres']));
});

test('knownPhrases covers every category in the region and the synced phrases', () => {
  const region = { a: [['a1', 'A']], b: [['b1', 'B'], ['b2', 'B']] };
  assert.deepEqual(knownPhrases(region, [['m1', 'M']]), new Set(['a1', 'b1', 'b2', 'm1']));
});

test("todaysRows is the day's category plus the bot's phrases", () => {
  const region = { b: [['b1', 'B']], a: [['a1', 'A']] };
  const mine = [['m1', 'M']];
  const days = [0, 1].map(day => todaysRows(region, mine, day));
  assert.deepEqual(days.map(d => d.category).sort(), ['a', 'b']);
  for (const d of days) assert.deepEqual(d.rows, [...region[d.category], ...mine]);
  assert.deepEqual(todaysRows({}, mine, 0), { category: null, rows: mine });
});

test('readSyncRows keeps well-formed new rows and tracks the highest id', () => {
  const have = new Set(['Che']);
  const out = readSyncRows(bytes('3|Bondi|Bus\n4|Che|Hey\n7|Bondi|Bus again\n5|Fiaca|Laziness\n'), have);
  assert.deepEqual(out, { rows: [['Bondi', 'Bus'], ['Fiaca', 'Laziness']], maxId: 7 });
  assert.ok(have.has('Fiaca'));
  assert.deepEqual(readSyncRows(bytes(''), new Set()), { rows: [], maxId: 0 });
});

test('readSyncRows drops malformed and unsafe rows but still counts their ids', () => {
  const lines = [
    '10|no translation',
    '11|a|b|c',
    'x|Bondi|Bus',
    '12|tab\there|x',
    '13|cr|carriage return\r',
    '14|bidi\u202ehere|x',
    '15|zero\u200bwidth|x',
    '16|soft\u00adhyphen|x',
    '17|bom\ufeff|x',
    '18|line\u2028sep|x',
    '19|Ok|Fine',
  ];
  const out = readSyncRows(bytes(lines.join('\n')), new Set());
  assert.deepEqual(out, { rows: [['Ok', 'Fine']], maxId: 19 });
});

test('readSyncRows drops a row that starts with a BOM and still counts long ids', () => {
  assert.deepEqual(readSyncRows(bytes('\ufeff5|a|b\n123456789012345678901|c|d\n'), new Set()),
    { rows: [['c', 'd']], maxId: 123456789012345678901 });
});

test('readSyncRows drops a row of invalid UTF-8 and keeps the rest', () => {
  const bad = new Uint8Array([...bytes('20|caf'), 0xe9, ...bytes('|coffee\n21|Mate|Tea\n')]);
  assert.deepEqual(readSyncRows(bad, new Set()), { rows: [['Mate', 'Tea']], maxId: 21 });
});

test('the bundled phrases are well formed', () => {
  assert.ok(Object.keys(phrases.es_AR).length >= 2);
  for (const [region, categories] of Object.entries(phrases)) {
    for (const [category, list] of Object.entries(categories)) {
      assert.notEqual(category, 'mine', `${region} bundles mine.psv`);
      assert.ok(list.length, `${region}/${category} is empty`);
      for (const r of list) {
        assert.equal(r.length, 2);
        assert.ok(r[0] && r[1], `${region}/${category}: ${r}`);
      }
    }
  }
});

test('cleanSettings keeps good values', () => {
  const good = { region: 'es_AR', delay: 0, learned: ['a|b'], last: 'a|b', mine: [['c', 'd']], swapped: true,
    pending: [{ key: 'a|b', on: false }] };
  assert.deepEqual(cleanSettings(good), good);
});

test('cleanSettings replaces malformed values with defaults', () => {
  const defaults = { region: 'es_AR', delay: 2, learned: [], last: null, mine: [], swapped: false, pending: [] };
  assert.deepEqual(cleanSettings(undefined), defaults);
  assert.deepEqual(cleanSettings(null), defaults);
  assert.deepEqual(cleanSettings({ region: 5, delay: 31, learned: 5, last: 7, mine: 'x', swapped: 'yes', pending: 1 }), defaults);
  assert.deepEqual(cleanSettings({ pending: [null, { key: 'a|b' }, { key: '', on: true }, { key: 'c|d', on: true }] }).pending,
    [{ key: 'c|d', on: true }]);
  assert.deepEqual(cleanSettings({ delay: 1.5 }).delay, 2);
  assert.deepEqual(cleanSettings({ delay: -1 }).delay, 2);
  assert.deepEqual(cleanSettings({ learned: ['a|b', null, 3, ''] }).learned, ['a|b']);
  assert.deepEqual(cleanSettings({ mine: [null, ['a'], ['a', ''], [1, 2], ['a', 'b', 'c'], { phrase: 'a' }, ['ok', 'fine']] }).mine,
    [['ok', 'fine']]);
});

test('toHex and fromHex round-trip UTF-8, as vozlocal-host encodes it', () => {
  assert.equal(toHex('Che|Hey'), '4368657c486579');
  assert.equal(toHex('¿Qué?'), 'c2bf5175c3a93f');
  assert.equal(fromHex('c2bf5175c3a93f'), '¿Qué?');
  for (const bad of ['', 'abc', 'zz', 'C2', 'ff', null]) assert.throws(() => fromHex(bad), bad);
});

test('readHostReply decodes learned keys and mine.psv rows', () => {
  const reply = { ok: true, learned: [toHex('Che|Hey')], mine: [toHex('Bondi|Bus'), toHex('Guita|Money')] };
  assert.deepEqual(readHostReply(reply), { learned: ['Che|Hey'], mine: [['Bondi', 'Bus'], ['Guita', 'Money']] });
});

test('readHostReply drops lines that are malformed or unsafe', () => {
  const bad = ['zz', 'ff', toHex('no separator'), toHex('a|b|c'), toHex('|x'), toHex('x|'), toHex('bi\u202edi|x'), toHex('cr|x\r')];
  assert.deepEqual(readHostReply({ ok: true, learned: [], mine: [...bad, toHex('Ok|Fine')] }),
    { learned: [], mine: [['Ok', 'Fine']] });
  assert.deepEqual(readHostReply({ ok: true, learned: [toHex('a|b|c'), 'zz', toHex('tab\t|x')], mine: [] }).learned, ['a|b|c']);
});

test('readHostReply refuses a failed or malformed reply', () => {
  for (const reply of [undefined, null, {}, { ok: false, error: 'bad region' }, { ok: true, learned: 'x', mine: [] }]) {
    assert.equal(readHostReply(reply), null);
  }
});
