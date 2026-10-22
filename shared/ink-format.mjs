// Platform-neutral InkDrive Ink Format v1. No file access or native dependencies.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA = /^[0-9a-f]{64}$/i;
const tools = new Set(['pen', 'pencil', 'marker']);
function requireThat(condition, message) { if (!condition) throw new Error(`Invalid InkDrive ink: ${message}`); }
function number(value, name, min = -1e9, max = 1e9) {
  requireThat(typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max, name);
}
function timestamp(value) { return typeof value === 'string' && /^\d{4}-\d\d-\d\dT.*Z$/.test(value) && Number.isFinite(Date.parse(value)); }
export function validateInk(doc) {
  requireThat(doc?.format === 'inkdrive.ink' && doc.version === 1, 'format/version');
  requireThat(UUID.test(doc.documentId) && SHA.test(doc.sourceRevision), 'document identity/revision');
  requireThat(doc.previewRevision == null || SHA.test(doc.previewRevision), 'preview revision');
  requireThat(Number.isSafeInteger(doc.inkRevision) && doc.inkRevision > 0, 'ink revision');
  requireThat(doc.parentRevision == null || SHA.test(doc.parentRevision), 'parent revision');
  requireThat(timestamp(doc.createdAt) && timestamp(doc.updatedAt) && Date.parse(doc.updatedAt) >= Date.parse(doc.createdAt), 'timestamps');
  requireThat(Array.isArray(doc.layers) && doc.layers.length > 0 && doc.layers.length <= 100, 'layers');
  const layers = new Set(), ids = new Set();
  for (const layer of doc.layers) {
    requireThat(typeof layer.id === 'string' && /^[a-zA-Z0-9_-]{1,64}$/.test(layer.id) && !layers.has(layer.id), 'layer ID');
    requireThat(typeof layer.name === 'string' && layer.name.length <= 128 && typeof layer.visible === 'boolean', 'layer');
    layers.add(layer.id);
  }
  requireThat(Array.isArray(doc.pages) && doc.pages.length > 0 && doc.pages.length <= 10000, 'pages');
  let total = 0;
  for (const page of doc.pages) {
    requireThat(UUID.test(page.id) && !ids.has(page.id), 'duplicate/invalid page ID'); ids.add(page.id);
    requireThat(['pdf', 'pptx', 'html-snapshot', 'image'].includes(page.kind), 'page kind');
    requireThat(page.unit === ({ pdf: 'pt', pptx: 'emu', 'html-snapshot': 'css-px', image: 'px' })[page.kind], 'page unit');
    requireThat([0, 90, 180, 270].includes(page.rotation), 'rotation');
    requireThat(page.bounds && typeof page.bounds === 'object', 'bounds');
    for (const field of ['x', 'y', 'width', 'height']) number(page.bounds[field], `bounds.${field}`, ['width', 'height'].includes(field) ? 1e-6 : -1e9);
    requireThat(Array.isArray(page.strokes) && page.strokes.length <= 100000, 'strokes');
    for (const stroke of page.strokes) {
      requireThat(UUID.test(stroke.id) && !ids.has(stroke.id), 'duplicate/invalid stroke ID'); ids.add(stroke.id);
      requireThat(layers.has(stroke.layerId) && tools.has(stroke.tool), 'stroke layer/tool');
      requireThat(/^#[0-9a-f]{6}$/i.test(stroke.color), 'stroke color'); number(stroke.opacity, 'stroke opacity', 0, 1);
      requireThat(timestamp(stroke.createdAt) && timestamp(stroke.updatedAt) && Date.parse(stroke.updatedAt) >= Date.parse(stroke.createdAt), 'stroke timestamps');
      requireThat(Array.isArray(stroke.transform) && stroke.transform.length === 6, 'transform');
      stroke.transform.forEach(v => number(v, 'transform')); inverseMatrix(stroke.transform);
      if (stroke.mask != null) {
        requireThat(Array.isArray(stroke.mask) && stroke.mask.length <= 100000 && typeof stroke.maskEvenOdd === 'boolean', 'mask');
        for (const command of stroke.mask) {
          requireThat(Array.isArray(command) && [3,3,5,7,1][command[0]] === command.length, 'mask command');
          command.forEach(v => number(v, 'mask coordinate'));
        }
      }
      if (stroke.outline != null) {
        requireThat(stroke.maskEvenOdd == null || typeof stroke.maskEvenOdd === 'boolean', 'outline fill rule');
        requireThat(Array.isArray(stroke.outline) && stroke.outline.length >= 2 && stroke.outline.length <= 100000, 'outline');
        for (const command of stroke.outline) {
          requireThat(Array.isArray(command) && Number.isInteger(command[0]) && [3,3,5,7,1][command[0]] === command.length, 'outline command');
          command.forEach(v => number(v, 'outline coordinate'));
        }
        requireThat(stroke.outline[0][0] === 0 && stroke.outline.at(-1)[0] === 4, 'outline must be closed');
      }
      requireThat(Array.isArray(stroke.samples) && stroke.samples.length > 0 && stroke.samples.length <= 100000, 'samples');
      let last = -1;
      for (const sample of stroke.samples) {
        number(sample.x, 'x'); number(sample.y, 'y'); number(sample.width, 'width', 1e-6); number(sample.height, 'height', 1e-6);
        number(sample.pressure, 'pressure', 0, 10); number(sample.opacity, 'sample opacity', 0, 1); number(sample.timeMs, 'timeMs', 0);
        requireThat(sample.timeMs >= last, 'non-monotonic stroke time'); last = sample.timeMs;
        if (++total > 2_000_000) throw new Error('InkDrive sample budget exceeded; load pages individually');
      }
    }
  }
  return doc;
}
export function transformPoint([a, b, c, d, e, f], { x, y }) { return { x: a * x + c * y + e, y: b * x + d * y + f }; }
export function inverseMatrix([a, b, c, d, e, f]) {
  const det = a * d - b * c;
  requireThat(Number.isFinite(det) && Math.abs(det) > 1e-12, 'singular transform');
  return [d / det, -b / det, -c / det, a / det, (c * f - d * e) / det, (b * e - a * f) / det];
}
export function pageMatrix(page) {
  const { x, y, width: w, height: h } = page.bounds;
  if (page.kind === 'pdf') return ({
    0: [1, 0, 0, -1, -x, y + h], 90: [0, 1, 1, 0, -y, -x],
    180: [-1, 0, 0, 1, x + w, -y], 270: [0, -1, -1, 0, y + h, x + w],
  })[page.rotation];
  return ({ 0: [1, 0, 0, 1, -x, -y], 90: [0, 1, -1, 0, y + h, -x],
    180: [-1, 0, 0, -1, x + w, y + h], 270: [0, -1, 1, 0, -y, x + w] })[page.rotation];
}
const n = value => String(Object.is(value, -0) ? 0 : value);
const matrix = values => `matrix(${values.map(n).join(' ')})`;
function polygon(points) { return `M${points.map(p => `${n(p.x)},${n(p.y)}`).join('L')}Z`; }
export function strokeOutline(stroke) {
  // One compound path per stroke: overlap of capsules must not accumulate opacity.
  // Samples must be interpolated by the native adapter; original pressure is metadata,
  // while width/height are actual document-unit nib dimensions (never multiplied twice).
  const parts = [];
  for (const p of stroke.samples) {
    const rx = p.width / 2, ry = p.height / 2;
    parts.push(`M${n(p.x + rx)},${n(p.y)}A${n(rx)} ${n(ry)} 0 1 1 ${n(p.x - rx)},${n(p.y)}A${n(rx)} ${n(ry)} 0 1 1 ${n(p.x + rx)},${n(p.y)}Z`);
  }
  for (let i = 1; i < stroke.samples.length; i++) {
    const a = stroke.samples[i - 1], b = stroke.samples[i], dx = b.x - a.x, dy = b.y - a.y, length = Math.hypot(dx, dy);
    if (length < 1e-12) continue;
    const nx = -dy / length, ny = dx / length;
    const radius = p => Math.sqrt((p.width * nx / 2) ** 2 + (p.height * ny / 2) ** 2);
    const ar = radius(a), br = radius(b);
    parts.push(polygon([{ x: a.x + nx * ar, y: a.y + ny * ar }, { x: a.x - nx * ar, y: a.y - ny * ar },
      { x: b.x - nx * br, y: b.y - ny * br }, { x: b.x + nx * br, y: b.y + ny * br }]));
  }
  return parts.join('');
}
export function renderPageSVG(doc, pageId) {
  validateInk(doc);
  const page = doc.pages.find(p => p.id === pageId); requireThat(page, 'page ID missing');
  const rotated = page.rotation % 180 !== 0, w = rotated ? page.bounds.height : page.bounds.width, h = rotated ? page.bounds.width : page.bounds.height;
  const visible = new Set(doc.layers.filter(l => l.visible).map(l => l.id));
  const paths = page.strokes.filter(s => visible.has(s.layerId)).map(stroke => {
    const alpha = stroke.samples[0].opacity;
    let path;
    if (stroke.outline) path = `<path d="${stroke.outline.map(c=>['M','L','Q','C','Z'][c[0]]+c.slice(1).map(n).join(' ')).join('')}" fill-rule="${stroke.maskEvenOdd ? 'evenodd' : 'nonzero'}" fill-opacity="${n(stroke.opacity)}"/>`;
    else if (stroke.samples.every(p => p.opacity === alpha)) path = `<path d="${strokeOutline(stroke)}" fill-opacity="${n(stroke.opacity * alpha)}"/>`;
    else path = stroke.samples.map((p,i) => `<path d="${strokeOutline({...stroke,samples:i ? [stroke.samples[i-1],p] : [p]})}" fill-opacity="${n(stroke.opacity*p.opacity)}"/>`).join('');
    const id = `mask-${stroke.id}`;
    const mask = stroke.mask ? `<defs><clipPath id="${id}"><path d="${stroke.mask.map(c=>['M','L','Q','C','Z'][c[0]]+c.slice(1).map(n).join(' ')).join('')}" clip-rule="${stroke.maskEvenOdd ? 'evenodd' : 'nonzero'}"/></clipPath></defs>` : '';
    return `<g transform="${matrix(stroke.transform)}" fill="${stroke.color}" fill-rule="nonzero">${mask}<g${stroke.mask ? ` clip-path="url(#${id})"` : ''}>${path}</g></g>`;
  }).join('');
  const clip = `page-clip-${page.id}`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${n(w)} ${n(h)}" role="img" aria-label="InkDrive vector ink"><defs><clipPath id="${clip}"><rect width="${n(w)}" height="${n(h)}"/></clipPath></defs><g clip-path="url(#${clip})"><g transform="${matrix(pageMatrix(page))}">${paths}</g></g></svg>`;
}
