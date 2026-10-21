import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, mkdir, rename, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { makePDF, makeInk } from '../windows/reference/fixture.mjs';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function setup(t) {
  const root = await mkdtemp(join(tmpdir(), 'inkdrive-commits-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const source = makePDF(1), ink = makeInk(source, 1); return { root, source, ink };
}
test('immutable commit verifies every payload and leaves the user source untouched', async t => {
  const { saveRevision, readCompleteRevision } = await import('../shared/ink-commits.mjs');
  const { root, source, ink } = await setup(t); const path = join(root, '수업.pdf'); await writeFile(path, source);
  const saved = await saveRevision(root, ink, { source, native: Buffer.from('native-archive'), deviceId: 'ipad-a' });
  const loaded = await readCompleteRevision(root, ink.documentId, saved.hash);
  assert.deepEqual(loaded.ink, ink); assert.equal(hash(loaded.source), ink.sourceRevision); assert.deepEqual(loaded.native, Buffer.from('native-archive'));
  assert.deepEqual(await readFile(path), source);
  await rename(path, join(root, '이름 변경.pdf'));
  assert.equal((await readCompleteRevision(root, ink.documentId, saved.hash)).ink.documentId, ink.documentId);
});
test('missing or corrupt new payload keeps the previous complete head displayable', async t => {
  const { saveRevision, readLatest } = await import('../shared/ink-commits.mjs');
  const { root, source, ink } = await setup(t);
  const first = await saveRevision(root, ink, { source, deviceId: 'ipad-a' });
  ink.inkRevision = 2; ink.pages[0].strokes[0].samples[0].width = 9;
  const second = await saveRevision(root, ink, { source, deviceId: 'ipad-a', parentCommit: first.hash });
  const objectPath = join(root, '.inkdrive/documents', ink.documentId, 'objects', second.commit.ink.sha256);
  const bytes = await readFile(objectPath); await writeFile(objectPath, bytes.subarray(0, 15));
  const pending = await readLatest(root, ink.documentId);
  assert.equal(pending.state, 'waiting'); assert.equal(pending.display.hash, first.hash); assert.equal(pending.display.ink.inkRevision, 1);
  await writeFile(objectPath, bytes); const ready = await readLatest(root, ink.documentId);
  assert.equal(ready.state, 'ready'); assert.equal(ready.display.hash, second.hash);
});
test('concurrent branches are preserved as a conflict rather than newest-wins overwrite', async t => {
  const { saveRevision, readLatest } = await import('../shared/ink-commits.mjs');
  const { root, source, ink } = await setup(t);
  const first = await saveRevision(root, ink, { source, deviceId: 'ipad-a' });
  ink.inkRevision = 2;
  const a = await saveRevision(root, ink, { source, deviceId: 'ipad-a', parentCommit: first.hash });
  ink.pages[0].strokes[0].color = '#FF0000';
  const b = await saveRevision(root, ink, { source, deviceId: 'ipad-b', parentCommit: first.hash });
  const state = await readLatest(root, ink.documentId, { preferred: first.hash });
  assert.equal(state.state, 'conflict'); assert.deepEqual(new Set(state.heads), new Set([a.hash, b.hash])); assert.equal(state.display.hash, first.hash);
});
test('wrong source revision and escaping identifiers cannot create a valid commit', async t => {
  const { saveRevision, readCompleteRevision } = await import('../shared/ink-commits.mjs');
  const { root, source, ink } = await setup(t);
  await assert.rejects(saveRevision(root, ink, { source: Buffer.from('wrong'), deviceId: 'ipad-a' }), /source/i);
  await assert.rejects(saveRevision(root, ink, { source, native: Buffer.alloc(0), deviceId: 'ipad-a' }), /native/i);
  await assert.rejects(readCompleteRevision(root, '../escape', 'a'.repeat(64)), /identity/i);
  await assert.rejects(readCompleteRevision(root, ink.documentId, '../escape'), /identity/i);
});
