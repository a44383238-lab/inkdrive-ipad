import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, utimes, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { prepareDay, completeJob } from '../scripts/daily-handoff.mjs';

const id = 'b6d7d083-53c8-4515-9f94-4b3c77074251';
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'inkdrive-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, '.inkdrive', 'lessons'), { recursive: true });
  await mkdir(join(root, 'Recordings'));
  await writeFile(join(root, '수업.pdf'), '%PDF-fixture');
  await writeFile(join(root, 'Recordings', 'lecture.m4a'), 'audio-fixture');
  const old = new Date(Date.now() - 300_000);
  for (const relative of ['수업.pdf', 'Recordings/lecture.m4a']) await utimes(join(root, relative), old, old);
  const lesson = { schemaVersion: 1, id, date: '2026-10-20', subject: '통계', title: '회귀분석', pdf: '수업.pdf',
    recordings: ['Recordings/lecture.m4a'], materials: [], endedAt: '2026-10-20T08:00:00Z', requestedOutputs: ['transcript', 'lecture-notes', 'review-questions'] };
  const manifest = join(root, '.inkdrive', 'lessons', id + '.json');
  await writeFile(manifest, JSON.stringify(lesson));
  return { root, lesson, manifest };
}
test('one stable ended lesson produces one job; rerun keeps the same fingerprint', async t => {
  const { root } = await fixture(t);
  const result = await prepareDay(root, '2026-10-20');
  assert.equal(result.jobs.length, 1); assert.equal(result.jobs[0].state, 'ready');
  const again = await prepareDay(root, '2026-10-20');
  assert.equal(again.jobs[0].fingerprint, result.jobs[0].fingerprint);
  assert.match(await readFile(join(root, result.jobs[0].prompt), 'utf8'), /복습문제/u);
});
test('unfinished class and audio still being written never reach ready', async t => {
  const { root, lesson, manifest } = await fixture(t);
  await writeFile(manifest, JSON.stringify({ ...lesson, endedAt: null }));
  assert.equal((await prepareDay(root, lesson.date)).blocked[0].reason, 'class-in-progress');
  await writeFile(manifest, JSON.stringify(lesson));
  const now = new Date(); await utimes(join(root, 'Recordings/lecture.m4a'), now, now);
  assert.equal((await prepareDay(root, lesson.date)).blocked[0].reason, 'file-not-stable');
});
test('missing recording, invalid path, and unreadable lesson are reported without overwriting sources', async t => {
  const { root, lesson, manifest } = await fixture(t);
  await writeFile(manifest, JSON.stringify({ ...lesson, recordings: ['../outside.m4a'] }));
  const result = await prepareDay(root, lesson.date);
  assert.equal(result.jobs.length, 0); assert.equal(result.blocked[0].reason, 'invalid-path');
  assert.equal(await readFile(join(root, '수업.pdf'), 'utf8'), '%PDF-fixture');
  await writeFile(manifest, '{');
  assert.equal((await prepareDay(root, lesson.date)).blocked[0].reason, 'invalid-manifest');
});
test('completion requires all real nonempty artifacts; changed sources invalidate prior completion', async t => {
  const { root, lesson } = await fixture(t);
  const result = await prepareDay(root, lesson.date);
  const job = result.jobs[0];
  await assert.rejects(completeJob(root, job.key));
  for (const name of ['transcript.md', 'notes.md', 'questions.md', 'evidence.md']) await writeFile(join(root, job.outputDir, name), '# 실제 결과\n검증 내용');
  await completeJob(root, job.key);
  assert.equal((await prepareDay(root, lesson.date)).jobs[0].state, 'complete');
  await writeFile(join(root, '수업.pdf'), '%PDF-changed');
  const old = new Date(Date.now() - 300_000); await utimes(join(root, '수업.pdf'), old, old);
  assert.equal((await prepareDay(root, lesson.date)).jobs[0].state, 'ready');
});
test('multiple recordings stay separate lecture units', async t => {
  const { root, lesson, manifest } = await fixture(t);
  await writeFile(join(root, 'Recordings/second.m4a'), 'second-audio');
  const old = new Date(Date.now() - 300_000); await utimes(join(root, 'Recordings/second.m4a'), old, old);
  await writeFile(manifest, JSON.stringify({ ...lesson, recordings: [...lesson.recordings, 'Recordings/second.m4a'] }));
  const result = await prepareDay(root, lesson.date);
  assert.equal(result.jobs.length, 2); assert.notEqual(result.jobs[0].key, result.jobs[1].key);
});
test('iPad expected checksum prevents processing an older Windows copy', async t => {
  const { root, lesson, manifest } = await fixture(t);
  const newer = createHash('sha256').update('%PDF-new-from-iPad').digest('hex');
  await writeFile(manifest, JSON.stringify({ ...lesson, sourceDigests: { '수업.pdf': newer } }));
  assert.equal((await prepareDay(root, lesson.date)).blocked[0]?.reason, 'source-not-synced');
  await writeFile(join(root, '수업.pdf'), '%PDF-new-from-iPad');
  const old = new Date(Date.now() - 300000); await utimes(join(root, '수업.pdf'), old, old);
  assert.equal((await prepareDay(root, lesson.date)).jobs[0].state, 'ready');
});
