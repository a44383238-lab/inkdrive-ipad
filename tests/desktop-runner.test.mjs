import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, utimes, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DesktopRunner, recentDates } from '../scripts/desktop-runner.mjs';

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'inkdrive-runner-')); t.after(() => rm(root, { force: true, recursive: true }));
  await mkdir(join(root, '.inkdrive/lessons'), { recursive: true });
  await writeFile(join(root, 'lesson.pdf'), 'pdf-source'); await writeFile(join(root, 'audio.m4a'), 'audio-source');
  const old = new Date(Date.now() - 300000);
  for (const file of ['lesson.pdf', 'audio.m4a']) await utimes(join(root, file), old, old);
  const id = 'aadea756-fbb3-49fc-8e10-46896771a14b';
  await writeFile(join(root, '.inkdrive/lessons', id + '.json'), JSON.stringify({
    schemaVersion: 1, id, date: '2026-10-20', subject: '통계', title: '평균', pdf: 'lesson.pdf', recordings: ['audio.m4a'], materials: [], endedAt: '2026-10-20T04:00:00Z'
  }));
  return root;
}
test('manual date selection crosses year boundaries and rejects impossible dates', () => {
  assert.deepEqual(recentDates('2026-01-01', 2), ['2026-01-01', '2025-12-31']);
  assert.throws(() => recentDates('2026-02-31'));
});
test('manual run with no classes finishes without invoking AI', async t => {
  const root = await mkdtemp(join(tmpdir(), 'inkdrive-empty-')); t.after(() => rm(root, { force: true, recursive: true }));
  const runner = new DesktopRunner({ root, executeJob: async () => { throw new Error('No AI should run'); } });
  const result = await runner.run(['2026-10-20']);
  assert.equal(result.phase, 'complete'); assert.equal(result.completed, 0); assert.equal(result.message, '처리할 새 수업이 없어요.');
});
test('double click shares one run; completed artifacts are skipped on the next run', async t => {
  const root = await fixture(t); let release; let executions = 0;
  const runner = new DesktopRunner({ root, executeJob: async job => {
    executions++; await new Promise(resolve => { release = resolve; });
    for (const file of ['transcript.md', 'notes.md', 'questions.md', 'evidence.md']) await writeFile(join(root, job.outputDir, file), '# 생성 결과\n테스트 엔진 경계');
  } });
  const first = runner.run(['2026-10-20']), second = runner.run(['2026-10-20']);
  void first.catch(() => {}); void second.catch(() => {});
  const deadline = Date.now() + 2000;
  while (!release && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(typeof release, 'function');
  release(); const [a, b] = await Promise.all([first, second]);
  assert.equal(a.completed, 1); assert.equal(b.completed, 1); assert.equal(executions, 1);
  assert.equal((await runner.run(['2026-10-20'])).completed, 0); assert.equal(executions, 1);
  assert.equal(await readFile(join(root, 'lesson.pdf'), 'utf8'), 'pdf-source');
});
test('missing results are reported as failure and the run lock is released for retry', async t => {
  const root = await fixture(t);
  const runner = new DesktopRunner({ root, executeJob: async () => {} });
  const result = await runner.run(['2026-10-20']);
  assert.equal(result.phase, 'failed'); assert.equal(result.failed, 1);
  assert.equal((await runner.run(['2026-10-20'])).failed, 1);
});
