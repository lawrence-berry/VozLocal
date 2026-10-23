import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DIM_MIN, DIM_MINUTES, DRIFT_RANGE, driftOffset, dimAt, parsePersonal, readCache, writeCache } from '../app/src/main/assets/lib.js';

const fakeStorage = () => {
  const data = new Map();
  return { getItem: k => data.get(k) ?? null, setItem: (k, v) => data.set(k, v) };
};

test('parsePersonal reads id|phrase|translation lines and drops anything unsafe', () => {
  const text = '1|Bondi|Bus\n2|Che|Hey\n\nnot a line\n3|a|b|c\n4|x\n5|‮evil|y\n6|ok|\x1b[31mred\nx|id|bad\n7|  Ñandú |Rhea \n';
  assert.deepEqual(parsePersonal(text), [['Bondi', 'Bus'], ['Che', 'Hey'], ['Ñandú', 'Rhea']]);
  assert.deepEqual(parsePersonal(''), []);
  assert.deepEqual(parsePersonal(undefined), []);
});

test('driftOffset stays within the range and is centred on a middle roll', () => {
  assert.deepEqual(driftOffset(() => 0.5), { x: 0, y: 0 });
  assert.deepEqual(driftOffset(() => 0), { x: -DRIFT_RANGE, y: -DRIFT_RANGE });
  for (let i = 0; i < 200; i++) {
    const { x, y } = driftOffset();
    assert.ok(Math.abs(x) <= DRIFT_RANGE && Math.abs(y) <= DRIFT_RANGE);
  }
});

test('dimAt falls in a line from 1 to DIM_MIN and stays there', () => {
  assert.equal(dimAt(0), 1);
  assert.equal(dimAt(-5), 1);
  assert.equal(dimAt(DIM_MINUTES), DIM_MIN);
  assert.equal(dimAt(DIM_MINUTES * 10), DIM_MIN);
  assert.ok(Math.abs(dimAt(DIM_MINUTES / 2) - (1 + DIM_MIN) / 2) < 1e-9);
});

test('the phrase cache round-trips and survives bad or missing storage', () => {
  const storage = fakeStorage();
  assert.equal(readCache(storage), null);
  writeCache(storage, [['Bondi', 'Bus']]);
  assert.deepEqual(readCache(storage), [['Bondi', 'Bus']]);

  storage.setItem('vozlocal.personal', '{not json');
  assert.equal(readCache(storage), null);

  const broken = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('full'); } };
  assert.equal(readCache(broken), null);
  assert.doesNotThrow(() => writeCache(broken, [['a', 'b']]));
});
