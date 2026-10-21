import { createHash } from 'node:crypto';

// Synthetic data only. No student PDF, microphone or iCloud access.
export function makePDF(count = 100) {
  const objects = [null, '<< /Type /Catalog /Pages 2 0 R >>', null, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  const kids = [];
  for (let i = 0; i < count; i++) {
    const page = objects.length, content = page + 1; kids.push(`${page} 0 R`);
    const stream = `0.92 0.94 0.97 rg 10 20 500 700 re f\n0.15 0.21 0.31 rg BT /F1 17 Tf 38 672 Td (InkDrive / vector reference / ${i + 1}) Tj ET\n0.72 0.77 0.85 RG 0.5 w 38 620 m 482 620 l S\n0.3 0.38 0.5 rg BT /F1 11 Tf 38 592 Td (Synthetic PDF. No PencilKit capture.) Tj ET\nBT /F1 10 Tf 38 570 Td (Crop: 10,20. Pressure widths and page identity preserved.) Tj ET\n0.35 0.45 0.6 RG 0.5 w 38 130 300 360 re S`;
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /CropBox [10 20 510 720] /Rotate ${(i % 4) * 90} /Resources << /Font << /F1 3 0 R >> >> /Contents ${content} 0 R >>`);
    objects.push(`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`);
  }
  objects[2] = `<< /Type /Pages /Count ${count} /Kids [${kids.join(' ')}] >>`;
  let data = '%PDF-1.7\n', offsets = [0];
  for (let i = 1; i < objects.length; i++) { offsets.push(Buffer.byteLength(data)); data += `${i} 0 obj\n${objects[i]}\nendobj\n`; }
  const xref = Buffer.byteLength(data);
  data += `xref\n0 ${objects.length}\n0000000000 65535 f \n` + offsets.slice(1).map(n => String(n).padStart(10, '0') + ' 00000 n \n').join('');
  data += `trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(data);
}
const id = value => `00000000-0000-4000-8000-${String(value).padStart(12, '0')}`;
export function makeInk(pdf, count = 100) {
  const date = '2026-10-21T00:00:00.000Z';
  return { format: 'inkdrive.ink', version: 1, documentId: id(1), sourceRevision: createHash('sha256').update(pdf).digest('hex'),
    inkRevision: 1, createdAt: date, updatedAt: date, layers: [{ id: 'main', name: '필기', visible: true }],
    pages: Array.from({ length: count }, (_, i) => ({ id: id(100 + i), kind: 'pdf', unit: 'pt', bounds: { x: 10, y: 20, width: 500, height: 700 },
      rotation: (i % 4) * 90, strokes: [
        { id: id(1000 + i * 3), layerId: 'main', tool: 'pen', color: '#2455D6', opacity: 1, createdAt: date, updatedAt: date,
          transform: [1, 0, 0, 1, 0, 0], samples: Array.from({ length: 130 }, (_, j) => ({ x: 60 + j * 2.7, y: 500 + Math.sin(j / 13) * 30,
            width: 1 + Math.sin(j / 26) ** 2 * 6, height: 1 + Math.sin(j / 26) ** 2 * 6, pressure: 0.2 + Math.sin(j / 26) ** 2 * 0.8, opacity: 1, timeMs: j * 5 })) },
        { id: id(1001 + i * 3), layerId: 'main', tool: 'marker', color: '#EAB54D', opacity: 0.35, createdAt: date, updatedAt: date,
          transform: [1, 0, 0, 1, 0, 0], samples: [{ x: 65, y: 430, width: 18, height: 18, pressure: 1, opacity: 1, timeMs: 0 }, { x: 300, y: 430, width: 18, height: 18, pressure: 1, opacity: 1, timeMs: 500 }] },
        { id: id(1002 + i * 3), layerId: 'main', tool: 'pen', color: '#D76C62', opacity: 1, createdAt: date, updatedAt: date,
          transform: [1, 0, 0, 1, 0, 0], samples: Array.from({ length: 100 }, (_, j) => ({ x: 200 + Math.cos(j * Math.PI * 2 / 99) * 100,
            y: 310 + Math.sin(j * Math.PI * 2 / 99) * 65, width: 2.2, height: 2.2, pressure: 0.5, opacity: 1, timeMs: j * 10 })) }
      ] })) };
}
