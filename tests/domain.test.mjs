import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanName, relativePath, orderedEntries, SingleFlight, LatestRequest } from '../src/domain.mjs';

test('names trim whitespace and reject path traversal / Windows-incompatible filenames', () => {
  assert.equal(cleanName('  통계학  '), '통계학');
  for (const name of ['', ' ', '.', '..', '../notes', 'a/b', 'a\\b', 'a:b', 'NUL', 'COM1.pdf', 'a.', 'a\u0000b']) {
    assert.throws(() => cleanName(name), undefined, name);
  }
});
test('rapid folder navigation applies only the latest requested list without dropping requests', async () => {
  const requests = new LatestRequest();
  const displayed = [];
  let finishOld;
  const first = requests.run(() => new Promise(resolve => { finishOld = resolve; }), value => displayed.push(value));
  await requests.run(async () => 'new folder', value => displayed.push(value));
  finishOld('old folder'); await first;
  assert.deepEqual(displayed, ['new folder']);
});
test('child paths stay relative and reject escaping parents', () => {
  assert.equal(relativePath('2학기/통계', '정리'), '2학기/통계/정리');
  assert.equal(relativePath('', '새 노트'), '새 노트');
  for (const parent of ['..', '/root', 'a/../b', 'C:/x', 'a\\b']) {
    assert.throws(() => relativePath(parent, 'note'));
  }
});
test('folders sort first, search is case-insensitive and source array is unchanged', () => {
  const rows = [{ name: 'Z.pdf', directory: false }, { name: '과목', directory: true }, { name: 'a.pdf', directory: false }];
  assert.deepEqual(orderedEntries(rows).map(x => x.name), ['과목', 'a.pdf', 'Z.pdf']);
  assert.deepEqual(orderedEntries(rows, 'Z').map(x => x.name), ['Z.pdf']);
  assert.equal(rows[0].name, 'Z.pdf');
});
test('double taps share one pending mutation; rejection releases the guard', async () => {
  const gate = new SingleFlight();
  let resolve;
  let calls = 0;
  const work = () => { calls++; return new Promise(r => { resolve = r; }); };
  const first = gate.run(work);
  const second = gate.run(work);
  await Promise.resolve();
  resolve('opened');
  assert.deepEqual(await Promise.all([first, second]), ['opened', 'opened']);
  assert.equal(calls, 1);
  await assert.rejects(gate.run(async () => { throw new Error('disk full'); }));
  assert.equal(await gate.run(async () => 'retry'), 'retry');
});
