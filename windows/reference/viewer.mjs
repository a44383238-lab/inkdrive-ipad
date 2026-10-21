import * as pdfjs from '/pdf.mjs';
import { validateInk, renderPageSVG } from '/ink-format.mjs';
pdfjs.GlobalWorkerOptions.workerSrc = '/pdf.worker.mjs';
const el = id => document.getElementById(id);
let documentPDF, ink, generation = 0, renderTask = null;
async function render() {
  if (!documentPDF) return;
  const turn = ++generation;
  if (renderTask) { renderTask.cancel(); try { await renderTask.promise; } catch {} renderTask = null; }
  const number = Math.max(1, Math.min(documentPDF.numPages, Number.parseInt(el('page').value, 10) || 1)); el('page').value = number;
  const zoom = Number(el('zoom').value), page = await documentPDF.getPage(number);
  if (turn !== generation) return;
  const model = ink?.pages[number - 1], crop = page.view;
  if (ink) {
    if (!model) throw new Error('필기 페이지가 없어요.');
    const pdfMismatch = model.kind === 'pdf' && (model.rotation !== page.rotate || Math.abs(model.bounds.x-crop[0])>1e-6 || Math.abs(model.bounds.y-crop[1])>1e-6 || Math.abs(model.bounds.width-(crop[2]-crop[0]))>1e-6 || Math.abs(model.bounds.height-(crop[3]-crop[1]))>1e-6);
    const adapterMismatch = model.kind !== 'pdf' && (page.rotate !== 0 || Math.abs(model.bounds.width/model.bounds.height-(crop[2]-crop[0])/(crop[3]-crop[1]))>0.002);
    if (pdfMismatch || adapterMismatch) throw new Error('문서와 필기 페이지 기준이 달라 표시를 중단했어요.');
  }
  const viewport = page.getViewport({ scale: zoom }), canvas = el('pdf'), dpr = window.devicePixelRatio || 1;
  // Limit raster background memory only. The SVG ink remains vector at every zoom.
  const pixelScale = Math.min(dpr, Math.sqrt(16_000_000 / (viewport.width * viewport.height)));
  canvas.width = Math.ceil(viewport.width * pixelScale); canvas.height = Math.ceil(viewport.height * pixelScale);
  canvas.style.width = viewport.width + 'px'; canvas.style.height = viewport.height + 'px';
  el('paper').style.width = viewport.width + 'px'; el('paper').style.height = viewport.height + 'px';
  el('paper').dataset.pdfTransform = JSON.stringify(viewport.transform);
  el('overlay').innerHTML = ink && el('ink').checked ? renderPageSVG(ink, model.id) : '';
  renderTask = page.render({ canvasContext: canvas.getContext('2d'), viewport, transform: [pixelScale, 0, 0, pixelScale, 0, 0] });
  await renderTask.promise; if (turn !== generation) return; renderTask = null;
  el('prev').disabled = number === 1; el('next').disabled = number === documentPDF.numPages;
  el('identity').textContent = ink ? `page ${model.id.slice(-4)} · source ${ink.sourceRevision.slice(0, 10)}` : 'PDF 내장 필기';
  el('status').textContent = `${number} / ${documentPDF.numPages} · ${Math.round(zoom * 100)}% · 문서 해시·페이지 좌표 확인됨`;
  document.body.dataset.rendered = `${number}:${zoom}`;
}
const update = () => render().catch(error => { if (error.name !== 'RenderingCancelledException') el('status').textContent = error.message; });
el('prev').onclick = () => { el('page').value = Number(el('page').value) - 1; update(); };
el('next').onclick = () => { el('page').value = Number(el('page').value) + 1; update(); };
for (const id of ['page', 'zoom', 'ink']) el(id).onchange = update;
try {
  const path=new URLSearchParams(location.search).get('path'),query='?path='+encodeURIComponent(path??'');
  const [pdfBytes, inkResponse] = await Promise.all([fetch(path?'/api/document'+query:'/fixture.pdf').then(r => {if(!r.ok)throw new Error('문서를 읽지 못했어요.');return r.arrayBuffer();}), fetch(path?'/api/document-ink'+query:'/fixture.ink.json').then(r => r.json())]);
  ink = path ? inkResponse.ink && validateInk(inkResponse.ink) : validateInk(inkResponse);
  const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', pdfBytes))].map(b => b.toString(16).padStart(2, '0')).join('');
  if (ink && hash !== (ink.previewRevision??ink.sourceRevision)) throw new Error('원본과 필기 버전이 달라요.');
  if(path){document.querySelector('h1').textContent=path.split('/').at(-1);document.querySelector('.bottom').textContent='읽기 전용 · iCloud 서재';document.querySelector('.eyebrow').textContent=inkResponse.state==='conflict'?'동시 변경 · 양쪽 버전 보존':inkResponse.state==='waiting'?'동기화 대기 · 이전 검증본':'LIBRARY';}
  documentPDF = await pdfjs.getDocument({ data: new Uint8Array(pdfBytes), isEvalSupported: false }).promise;
  el('pages').textContent = `/ ${documentPDF.numPages}`; el('page').max = documentPDF.numPages;
  await render();
} catch (error) { el('status').textContent = error.message; }
