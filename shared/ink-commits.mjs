// Reference content-addressed store. Explicit root only; never discovers or migrates user files.
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, open, readFile, readdir, realpath, rename, stat, unlink } from 'node:fs/promises';
import { dirname } from 'node:path';
import { validateInk } from './ink-format.mjs';
import { resolveInside } from '../scripts/daily-handoff.mjs';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hashPattern = /^[0-9a-f]{64}$/;
function check(value, message) { if (!value) throw new Error(`InkDrive revision: ${message}`); }
function identity(id, hash) { check(idPattern.test(id) && (hash == null || hashPattern.test(hash)), 'invalid identity'); }
const base = id => `.inkdrive/documents/${id}`;
export function canonicalJSON(value) {
  const sort = item => Array.isArray(item) ? item.map(sort) : item !== null && typeof item === 'object'
    ? Object.fromEntries(Object.keys(item).sort().map(key => [key, sort(item[key])])) : item;
  return Buffer.from(JSON.stringify(sort(value)) + '\n');
}
async function immutable(root, relative, bytes) {
  const destination = await resolveInside(root, relative, true);
  await mkdir(dirname(destination), { recursive: true });
  try { const existing = await readFile(destination); check(existing.equals(bytes), 'immutable content differs'); return; }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const temporary = destination + '.' + randomUUID() + '.partial';
  const file = await open(temporary, 'wx');
  try { await file.writeFile(bytes); await file.sync(); } finally { await file.close(); }
  try {
    // Both racing writers use a content hash as destination and therefore identical bytes.
    try { check((await readFile(destination)).equals(bytes), 'immutable content differs'); await unlink(temporary); return; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    await rename(temporary, destination);
  } catch (error) { await unlink(temporary).catch(() => {}); throw error; }
}
export async function saveRevision(root, ink, { source, native = null, preview = null, deviceId, parentCommit = null } = {}) {
  validateInk(ink); identity(ink.documentId, parentCommit);
  check(typeof deviceId === 'string' && /^[a-zA-Z0-9_-]{1,64}$/.test(deviceId), 'device ID');
  check(Buffer.isBuffer(source) && source.length > 0 && source.length <= 256_000_000, 'source bytes');
  check(digest(source) === ink.sourceRevision, 'source hash mismatch');
  check(preview == null ? ink.previewRevision == null : Buffer.isBuffer(preview) && preview.length > 0 && preview.length <= 256_000_000 && digest(preview) === ink.previewRevision, 'preview hash mismatch');
  check(native == null || Buffer.isBuffer(native) && native.length > 0 && native.length <= 128_000_000, 'native archive');
  root = await realpath(root);
  if (parentCommit) {
    const parent = await readCompleteRevision(root, ink.documentId, parentCommit);
    check(ink.inkRevision > parent.ink.inkRevision, 'revision must advance');
  }
  const inkBytes = canonicalJSON(ink);
  const descriptor = bytes => ({ sha256: digest(bytes), bytes: bytes.length });
  const commit = { format: 'inkdrive.commit', version: 1, documentId: ink.documentId, deviceId, createdAt: new Date().toISOString(),
    parents: parentCommit ? [parentCommit] : [], source: descriptor(source), ink: descriptor(inkBytes), native: native == null ? null : descriptor(native) };
  if (preview) commit.preview = descriptor(preview);
  for (const [ref, bytes] of [[commit.source, source], [commit.ink, inkBytes], [commit.native, native], [commit.preview, preview]])
    if (ref) await immutable(root, `${base(ink.documentId)}/objects/${ref.sha256}`, bytes);
  const commitBytes = canonicalJSON(commit), hash = digest(commitBytes);
  // Publishing this file last does not promise iCloud arrival order: readers verify all payloads.
  await immutable(root, `${base(ink.documentId)}/commits/${hash}.json`, commitBytes);
  return { hash, commit };
}
export async function readCompleteRevision(root, documentId, hash) {
  identity(documentId, hash); root = await realpath(root);
  check(hashPattern.test(hash), 'invalid identity');
  const path = await resolveInside(root, `${base(documentId)}/commits/${hash}.json`);
  check((await stat(path)).size <= 100_000, 'oversized commit');
  const bytes = await readFile(path); check(digest(bytes) === hash, 'commit hash mismatch');
  const commit = JSON.parse(bytes);
  check(commit.format === 'inkdrive.commit' && commit.version === 1 && commit.documentId === documentId, 'commit identity/version mismatch');
  check(Array.isArray(commit.parents) && commit.parents.length <= 1 && commit.parents.every(p => hashPattern.test(p) && p !== hash), 'parents');
  async function payload(ref, max) {
    check(ref && hashPattern.test(ref.sha256) && Number.isSafeInteger(ref.bytes) && ref.bytes > 0 && ref.bytes <= max, 'payload descriptor');
    const object = await resolveInside(root, `${base(documentId)}/objects/${ref.sha256}`);
    check((await stat(object)).size === ref.bytes, 'payload length mismatch');
    const data = await readFile(object); check(digest(data) === ref.sha256, 'payload hash mismatch'); return data;
  }
  const source = await payload(commit.source, 256_000_000), inkBytes = await payload(commit.ink, 128_000_000);
  const native = commit.native == null ? null : await payload(commit.native, 128_000_000);
  const preview = commit.preview == null ? null : await payload(commit.preview, 256_000_000);
  const ink = validateInk(JSON.parse(inkBytes));
  check(ink.documentId === documentId && ink.sourceRevision === commit.source.sha256, 'ink/source identity mismatch');
  check(preview == null ? ink.previewRevision == null : ink.previewRevision === commit.preview.sha256, 'ink/preview identity mismatch');
  return { hash, commit, source, ink, native, preview };
}
export async function readLatest(root, documentId, { preferred = null } = {}) {
  identity(documentId, preferred); root = await realpath(root);
  let paths;
  try { paths = await readdir(await resolveInside(root, `${base(documentId)}/commits`)); }
  catch (error) { if (error.code === 'ENOENT') return { state: 'empty', display: null, heads: [], pending: [] }; throw error; }
  const complete = new Map(), pending = [];
  for (const name of paths.filter(n => /^[0-9a-f]{64}\.json$/.test(n)).sort()) {
    const hash = name.slice(0, -5);
    try {
      const value = await readCompleteRevision(root, documentId, hash);
      // Do not retain a full source PDF and native archive for every historical commit.
      complete.set(hash, { hash, commit: value.commit });
    }
    catch (error) { pending.push({ hash, reason: error.code === 'ENOENT' ? 'payload-not-arrived' : 'verification-failed' }); }
  }
  // A child without its parent graph is not eligible to silently replace verified history.
  let changed;
  do {
    changed = false;
    for (const [hash, value] of complete) if (value.commit.parents.some(p => !complete.has(p))) {
      complete.delete(hash); pending.push({ hash, reason: 'parent-not-arrived' }); changed = true;
    }
  } while (changed);
  const ancestors = new Set([...complete.values()].flatMap(v => v.commit.parents));
  const heads = [...complete.keys()].filter(hash => !ancestors.has(hash));
  const selected = heads.length === 1 ? heads[0] : preferred && complete.has(preferred) ? preferred : null;
  const display = selected ? await readCompleteRevision(root, documentId, selected) : null;
  return { state: heads.length > 1 ? 'conflict' : pending.length ? 'waiting' : heads.length ? 'ready' : 'empty', display, heads, pending };
}
