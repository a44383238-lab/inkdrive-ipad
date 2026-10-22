import test from 'node:test';
import assert from 'node:assert/strict';
import { renderPageSVG, validateInk } from '../shared/ink-format.mjs';

function fixture() {
  const born = '2026-10-22T00:00:00.000Z';
  return { format: 'inkdrive.ink', version: 1, documentId: '00000000-0000-4000-8000-000000000001',
    sourceRevision: 'a'.repeat(64), inkRevision: 1, createdAt: born, updatedAt: born,
    layers: [{id:'main',name:'ink',visible:true}], pages: [{id:'00000000-0000-4000-8000-000000000002',
      kind:'pdf',unit:'pt',bounds:{x:0,y:0,width:595,height:842},rotation:0,strokes:[{
        id:'00000000-0000-4000-8000-000000000003',layerId:'main',tool:'pen',color:'#000000',opacity:1,
        createdAt:born,updatedAt:born,transform:[1,0,0,1,0,0],
        samples:[{x:10,y:20,width:1,height:1,pressure:0.2,opacity:1,timeMs:0}],
        outline:[[0,10,20],[1,90,20],[1,90,25],[1,10,21],[4]],
      }]}]};
}
test('Perfect Freehand export fills its exact outline instead of reconstructing another brush', () => {
  const doc=fixture(), svg=renderPageSVG(doc,doc.pages[0].id);
  assert.match(svg,/d="M10 20L90 20L90 25L10 21Z"/);
  assert.match(svg,/fill-opacity="1"/);
  assert.doesNotMatch(svg,/A0\.5/);
});
test('malformed custom outlines are rejected before SVG rendering', () => {
  for(const outline of [[[9,1,2]],[[0,1,Infinity]],[[0,1]],'bad',[]]) {
    const doc=fixture();doc.pages[0].strokes[0].outline=outline;
    assert.throws(()=>validateInk(doc),/outline/);
  }
});
