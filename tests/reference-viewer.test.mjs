import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import http from 'node:http';
import { createReferenceServer } from '../windows/reference/server.mjs';
import { validateInk, renderPageSVG } from '../shared/ink-format.mjs';

test('reference server serves a hash-matched 100-page PDF/ink pair without reading the real library', async t => {
  const server = createReferenceServer(); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(base+'/?path=real-document.pdf')).status,200);
  const bytes = Buffer.from(await (await fetch(base + '/fixture.pdf')).arrayBuffer());
  const ink = validateInk(await (await fetch(base + '/fixture.ink.json')).json());
  assert.equal(ink.pages.length, 100); assert.match(bytes.toString(), /\/Count 100/);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), ink.sourceRevision);
  assert.equal(new Set(ink.pages.map(p => p.id)).size, 100);
  for (const index of [0, 1, 2, 3, 99]) assert.match(renderPageSVG(ink, ink.pages[index].id), /<path /);
  assert.equal((await fetch(base + '/api/library')).status, 404);
  assert.equal((await fetch(base + '/fixture.pdf', { method: 'POST' })).status, 403);
  const wrongHost = await new Promise((resolve, reject) => {
    http.get(base + '/fixture.pdf', { headers: { Host: 'untrusted.invalid' } }, response => { response.resume(); resolve(response.statusCode); }).on('error', reject);
  });
  assert.equal(wrongHost, 403);
});
