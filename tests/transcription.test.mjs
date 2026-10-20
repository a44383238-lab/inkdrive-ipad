import test from 'node:test';
import assert from 'node:assert/strict';
import { chunkRanges, mergeSegments } from '../scripts/transcribe.mjs';
test('long recordings keep complete coverage with two seconds of context', () => {
  assert.deepEqual(chunkRanges(650), [
    { index: 0, start: 0, end: 300 }, { index: 1, start: 298, end: 600 }, { index: 2, start: 598, end: 650 },
  ]);
  assert.deepEqual(chunkRanges(300), [{ index: 0, start: 0, end: 300 }]);
  assert.throws(() => chunkRanges(0));
});
test('timestamps become absolute, identical overlap is removed, differing words remain', () => {
  const chunks = [
    { start: 0, transcription: [{ offsets: { from: 298000, to: 299000 }, text: '표본 평균' }] },
    { start: 298, transcription: [{ offsets: { from: 0, to: 1000 }, text: '표본 평균' }, { offsets: { from: 1000, to: 2500 }, text: '분산입니다' }] },
  ];
  assert.deepEqual(mergeSegments(chunks), [
    { from: 298000, to: 299000, text: '표본 평균' }, { from: 299000, to: 300500, text: '분산입니다' },
  ]);
});
