import test from 'node:test';
import assert from 'node:assert/strict';
import { parentFolder, folderDestination } from '../src/domain.mjs';

test('library root is a hard boundary and repeated root taps keep the current listing', () => {
  assert.equal(parentFolder(''), '');
  assert.equal(parentFolder('통계'), '');
  assert.equal(parentFolder('통계/강의'), '통계');
  assert.deepEqual(folderDestination('', ''), { path: '', changed: false });
  assert.deepEqual(folderDestination('통계', '통계'), { path: '통계', changed: false });
  assert.deepEqual(folderDestination('통계/강의', ''), { path: '', changed: true });
});
test('folder navigation cannot escape the selected iCloud library', () => {
  for (const path of ['..', '../통계', '/통계', 'a//b', 'a/../b']) {
    assert.throws(() => folderDestination('', path));
  }
});
