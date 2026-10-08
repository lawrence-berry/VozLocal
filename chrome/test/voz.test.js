import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { categoryIndex, cleanSettings, dayNumber, fromHex, key, queueMark, readHostReply, toHex, withoutSent, pick, todaysChoice } from '../extension/lib/voz.js';

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
    pending: [{ key: 'a|b', on: false, at: 5 }], linked: true };
  assert.deepEqual(cleanSettings(good), good);
});

test('cleanSettings replaces malformed values with defaults', () => {
  const defaults = { region: 'es_AR', delay: 2, learned: [], last: null, mine: [], swapped: false, pending: [], linked: false };
  assert.deepEqual(cleanSettings(undefined), defaults);
  assert.deepEqual(cleanSettings(null), defaults);
  assert.deepEqual(cleanSettings({ region: 5, delay: 31, learned: 5, last: 7, mine: 'x', swapped: 'yes', pending: 1, linked: 1 }), defaults);
  assert.deepEqual(cleanSettings({ pending: [null, { key: 'a|b', at: 1 }, { key: '', on: true, at: 1 }, { key: 'x|y', on: true },
    { key: 'c|d', on: true, at: 2 }] }).pending, [{ key: 'c|d', on: true, at: 2 }]);
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

test('queueMark keeps only the latest mark for each phrase', () => {
  let pending = queueMark([], 'a|b', true, 1);
  pending = queueMark(pending, 'c|d', true, 2);
  pending = queueMark(pending, 'a|b', false, 3);
  assert.deepEqual(pending, [{ key: 'c|d', on: true, at: 2 }, { key: 'a|b', on: false, at: 3 }]);
});

test('withoutSent drops only the marks that were sent', () => {
  const sent = [{ key: 'a|b', on: true, at: 1 }];
  const now = [...sent, { key: 'c|d', on: true, at: 2 }, { key: 'a|b', on: false, at: 3 }];
  assert.deepEqual(withoutSent(now, sent), [{ key: 'c|d', on: true, at: 2 }, { key: 'a|b', on: false, at: 3 }]);
});

const region = { a: [['a1', 'A'], ['a2', 'A']], b: [['b1', 'B']], c: [['c1', 'C'], ['c2', 'C']] };
const mineRows = [['m1', 'M']];
const keys = rows => new Set(rows.map(key));
// The day whose category is `name`.
const dayOf = name => Array.from({ length: 3 }, (_, d) => d).find(d => ['a', 'b', 'c'][categoryIndex(3, d)] === name);

test("todaysChoice is the day's category plus mine.psv, while it has unlearned phrases", () => {
  const day = dayOf('a');
  assert.deepEqual(todaysChoice(region, mineRows, new Set([key(region.a[0])]), day),
    { category: 'a', rows: [region.a[1], mineRows[0]] });
});

test('todaysChoice moves to the next category with unlearned phrases once the day\'s are all learned', () => {
  const day = dayOf('a');
  assert.deepEqual(todaysChoice(region, mineRows, keys(region.a), day).category, 'b');
  assert.deepEqual(todaysChoice(region, mineRows, keys([...region.a, ...region.b]), day).category, 'c');
  const fromC = todaysChoice(region, [], keys([...region.c, region.a[0]]), dayOf('c'));
  assert.deepEqual(fromC, { category: 'a', rows: [region.a[1]] });  // wraps round to the start
});

test('todaysChoice never offers a learned phrase', () => {
  const learned = keys([region.a[0], region.b[0], mineRows[0]]);
  for (const day of [0, 1, 2]) {
    for (const row of todaysChoice(region, mineRows, learned, day).rows) assert.ok(!learned.has(key(row)), row[0]);
  }
});

test('todaysChoice offers only mine.psv once every category is learned, then nothing', () => {
  const allRegion = keys(Object.values(region).flat());
  assert.deepEqual(todaysChoice(region, mineRows, allRegion, 0), { category: null, rows: mineRows });
  assert.deepEqual(todaysChoice(region, mineRows, new Set([...allRegion, key(mineRows[0])]), 0), { category: null, rows: [] });
  assert.deepEqual(todaysChoice({}, [], new Set(), 0), { category: null, rows: [] });
});
