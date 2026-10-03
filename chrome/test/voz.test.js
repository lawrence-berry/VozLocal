import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { categoryIndex, dayNumber, key, pick, readSyncRows, todaysRows } from '../extension/lib/voz.js';

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
const always = i => () => i / rows.length;  // rand() that lands on index i of a 3-item pool

test('pick skips learned phrases and the last one shown', () => {
  const learned = new Set([key(rows[0])]);
  for (let i = 0; i < 50; i++) {
    assert.deepEqual(pick(rows, learned, key(rows[1])), rows[2]);
  }
});

test('pick falls back: any unlearned, then any not last, then any', () => {
  // Only "dos" is unlearned, and it was shown last: an unlearned repeat beats a learned phrase.
  assert.deepEqual(pick(rows, new Set([key(rows[0]), key(rows[2])]), key(rows[1])), rows[1]);
  // All learned: anything but the last.
  const all = new Set(rows.map(key));
  for (let i = 0; i < 50; i++) assert.notDeepEqual(pick(rows, all, key(rows[0])), rows[0]);
  // A category's only phrase shows every time.
  assert.deepEqual(pick([rows[0]], new Set(), key(rows[0])), rows[0]);
  assert.equal(pick([], new Set(), null), null);
});

test('pick uses the random source it is given', () => {
  assert.deepEqual(pick(rows, new Set(), null, always(0)), rows[0]);
  assert.deepEqual(pick(rows, new Set(), null, always(2)), rows[2]);
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
