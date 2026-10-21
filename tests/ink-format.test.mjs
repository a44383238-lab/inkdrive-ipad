import test from 'node:test';
import assert from 'node:assert/strict';

const docId = '00000000-0000-4000-8000-000000000001';
const pageId = '00000000-0000-4000-8000-000000000002';
const strokeId = '00000000-0000-4000-8000-000000000003';
export function fixture() {
  return { format: 'inkdrive.ink', version: 1, documentId: docId, sourceRevision: 'a'.repeat(64), inkRevision: 1,
    createdAt: '2026-10-21T00:00:00.000Z', updatedAt: '2026-10-21T00:00:00.000Z',
    layers: [{ id: 'main', name: '필기', visible: true }], pages: [{ id: pageId, kind: 'pdf', unit: 'pt',
      bounds: { x: 10, y: 20, width: 500, height: 700 }, rotation: 0, strokes: [{ id: strokeId, layerId: 'main', tool: 'pen',
        color: '#2455D6', opacity: 0.8, createdAt: '2026-10-21T00:00:00.000Z', updatedAt: '2026-10-21T00:00:00.000Z',
        transform: [1, 0, 0, 1, 0, 0], samples: [{ x: 30, y: 100, width: 2, height: 2, pressure: 0.2, opacity: 1, timeMs: 0 },
          { x: 100, y: 130, width: 8, height: 8, pressure: 0.9, opacity: 1, timeMs: 80 }] }] }] };
}

test('portable ink preserves pressures, sizes, stable IDs and fractional document coordinates', async () => {
  const { validateInk } = await import('../shared/ink-format.mjs');
  const data = fixture(); data.pages[0].strokes[0].samples[0].x = 30.125;
  assert.deepEqual(validateInk(JSON.parse(JSON.stringify(data))), data);
  data.pages.reverse(); assert.equal(validateInk(data).pages[0].id, pageId);
});

test('PDF crop origin and every rotation map corners correctly and round trip', async () => {
  const { pageMatrix, transformPoint, inverseMatrix } = await import('../shared/ink-format.mjs');
  const page = fixture().pages[0];
  for (const [rotation, expected] of [[0, [0, 700]], [90, [0, 0]], [180, [500, 0]], [270, [700, 500]]]) {
    page.rotation = rotation; const matrix = pageMatrix(page);
    const point = transformPoint(matrix, { x: 10, y: 20 });
    assert.deepEqual([point.x, point.y], expected);
    const original = transformPoint(inverseMatrix(matrix), transformPoint(matrix, { x: 143.125, y: 345.25 }));
    assert.ok(Math.abs(original.x - 143.125) < 1e-8); assert.ok(Math.abs(original.y - 345.25) < 1e-8);
  }
});

test('shared vector output uses paths and viewBox, preserves transform and ignores screen scale', async () => {
  const { renderPageSVG } = await import('../shared/ink-format.mjs');
  const data = fixture(); data.pages[0].strokes[0].transform = [1, 0, 0, 1, 12, -3];
  const svg = renderPageSVG(data, pageId);
  assert.match(svg, /viewBox="0 0 500 700"/); assert.match(svg, /<path /);
  assert.match(svg, /matrix\(1 0 0 1 12 -3\)/); assert.doesNotMatch(svg, /<image|data:image|<script/i);
  assert.match(svg, /fill="#2455D6"/); assert.match(svg, /fill-opacity="0.8"/);
  assert.match(svg, /A1 1 /); // Round caps must remain true vector ellipses at 400%, not 16-sided approximations.
});

test('malformed data, ambiguous identities, unsupported versions and injected SVG values fail closed', async () => {
  const { validateInk } = await import('../shared/ink-format.mjs');
  for (const change of [d => d.version = 2, d => d.sourceRevision = 'unknown', d => d.pages.push(structuredClone(d.pages[0])),
    d => d.pages[0].strokes[0].samples[0].x = Infinity, d => d.pages[0].strokes[0].samples[0].width = -1,
    d => d.pages[0].strokes[0].samples[1].timeMs = -2, d => d.pages[0].strokes[0].color = 'red" onload="alert(1)',
    d => d.pages[0].strokes[0].layerId = 'missing', d => d.pages[0].rotation = 45,
    d => d.pages[0].strokes[0].transform = [0,0,0,0,0,0], d => d.pages[0].unit = 'px',
    d => d.pages[0].strokes.push(structuredClone(d.pages[0].strokes[0]))]) {
    const bad = fixture(); change(bad); assert.throws(() => validateInk(bad));
  }
});

test('hidden layers do not render; varying opacity and eraser masks remain vector', async () => {
  const { renderPageSVG } = await import('../shared/ink-format.mjs');
  const data = fixture(); data.layers[0].visible = false;
  assert.doesNotMatch(renderPageSVG(data, pageId), /<path /);
  data.layers[0].visible = true; data.pages[0].strokes[0].samples[1].opacity = 0.4;
  const stroke=data.pages[0].strokes[0];stroke.mask=[[0,0,0],[1,50,0],[1,50,50],[4]];stroke.maskEvenOdd=true;
  const svg=renderPageSVG(data,pageId);assert.match(svg,/clip-rule="evenodd"/);assert.match(svg,/fill-opacity="0.32000000000000006"/);assert.doesNotMatch(svg,/<image/);
  stroke.mask=[[9,1,1]];assert.throws(()=>renderPageSVG(data,pageId),/mask/);
});
