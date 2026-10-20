import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, open, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveInside } from './daily-handoff.mjs';

export function chunkRanges(seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('Invalid audio duration');
  const ranges = [];
  for (let start = 0, index = 0; start < seconds; start += 300, index++) {
    ranges.push({ index, start: Math.max(0, start - (index ? 2 : 0)), end: Math.min(seconds, start + 300) });
  }
  return ranges;
}
export function mergeSegments(chunks) {
  const result = [];
  for (const chunk of chunks) for (const segment of chunk.transcription) {
    if (!Number.isFinite(segment.offsets?.from) || !Number.isFinite(segment.offsets?.to)) throw new Error('Missing timestamps');
    const row = { from: Math.round(chunk.start * 1000 + segment.offsets.from), to: Math.round(chunk.start * 1000 + segment.offsets.to), text: segment.text.trim() };
    if (!row.text) continue;
    if (result.slice(-8).some(old => old.text === row.text && Math.abs(old.from - row.from) <= 1500 && old.to >= row.from)) continue;
    result.push(row);
  }
  return result.sort((a, b) => a.from - b.from);
}
async function digest(path) {
  const hash = createHash('sha256'); for await (const chunk of createReadStream(path)) hash.update(chunk); return hash.digest('hex');
}
async function execute(command, args, logPath) {
  await new Promise((done, reject) => {
    const process = spawn(command, args, { windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    const logs = [];
    let bytes = 0;
    const collect = chunk => { bytes += chunk.length; if (bytes < 5_000_000) logs.push(chunk); };
    process.stdout.on('data', collect); process.stderr.on('data', collect);
    process.once('error', reject);
    process.once('close', code => {
      void writeFile(logPath, Buffer.concat(logs)).then(() => code === 0 ? done() : reject(new Error(`Local transcription tool exited ${code}; see ${logPath}`)), reject);
    });
  });
}
async function wavDuration(path) {
  const file = await open(path, 'r');
  try {
    const header = Buffer.alloc(65536); const { bytesRead } = await file.read(header, 0, header.length, 0);
    if (header.toString('ascii', 0, 4) !== 'RIFF' || header.toString('ascii', 8, 12) !== 'WAVE') throw new Error('Unsupported WAV');
    let byteRate = 0;
    for (let index = 12; index + 8 < bytesRead;) {
      const tag = header.toString('ascii', index, index + 4), size = header.readUInt32LE(index + 4);
      if (tag === 'fmt ') byteRate = header.readUInt32LE(index + 16);
      if (tag === 'data' && byteRate) return size / byteRate;
      index += 8 + size + (size % 2);
    }
    throw new Error('No PCM audio data');
  } finally { await file.close(); }
}
async function atomic(path, data) { const temp = path + '.partial'; await writeFile(temp, data); await rename(temp, path); }
export async function transcribeJob(root, key, runtime) {
  if (!/^[0-9a-f-]{36}-\d+-[0-9a-f]{16}$/i.test(key)) throw new Error('Invalid job key');
  root = await (await import('node:fs/promises')).realpath(root);
  const job = JSON.parse(await readFile(await resolveInside(root, `.inkdrive/jobs/${key}.json`), 'utf8'));
  if (job.key !== key || job.outputDir !== `AI/${job.date}/${key}` || !job.sources?.[1]) throw new Error('Invalid job');
  const audio = await resolveInside(root, job.sources[1].path);
  if (await digest(audio) !== job.sources[1].sha256) throw new Error('Audio changed after handoff');
  for (const path of [runtime.ffmpeg, runtime.whisper, runtime.model]) if (!(await stat(path)).isFile()) throw new Error('Local transcription runtime missing');
  const work = await resolveInside(root, `${job.outputDir}/.transcription`, true); await mkdir(work, { recursive: true });
  const wav = join(work, 'audio-16k.wav');
  const identity = createHash('sha256').update(JSON.stringify({ audio: job.sources[1].sha256, model: await digest(runtime.model), engine: await digest(runtime.whisper), language: 'ko', chunk: 300, overlap: 2 })).digest('hex');
  let state;
  try { state = JSON.parse(await readFile(join(work, 'state.json'), 'utf8')); } catch {}
  if (state?.identity !== identity) {
    await execute(runtime.ffmpeg, ['-nostdin', '-y', '-i', audio, '-map', '0:a:0', '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', wav], join(work, 'decode.log'));
    state = { identity, completed: [], duration: await wavDuration(wav), engine: 'whisper.cpp', model: runtime.model, language: 'ko', complete: false };
    await atomic(join(work, 'state.json'), JSON.stringify(state, null, 2));
  }
  const chunks = [];
  for (const range of chunkRanges(state.duration)) {
    const base = join(work, `chunk-${String(range.index).padStart(4, '0')}`);
    let output;
    if (state.completed.includes(range.index)) {
      try { output = JSON.parse(await readFile(base + '.json', 'utf8')); } catch {}
    }
    const reused = Array.isArray(output?.transcription);
    if (!reused) {
      await execute(runtime.ffmpeg, ['-nostdin', '-y', '-ss', String(range.start), '-i', wav, '-t', String(range.end - range.start), '-c:a', 'pcm_s16le', base + '.wav'], base + '-decode.log');
      await execute(runtime.whisper, ['-m', runtime.model, '-f', base + '.wav', '-l', 'ko', '-t', String(runtime.threads ?? 6), '-oj', '-of', base + '.partial'], base + '-whisper.log');
      output = JSON.parse(await readFile(base + '.partial.json', 'utf8'));
      if (!Array.isArray(output.transcription)) throw new Error('Whisper returned no transcription array');
      await rename(base + '.partial.json', base + '.json');
      if (!state.completed.includes(range.index)) state.completed.push(range.index);
      await atomic(join(work, 'state.json'), JSON.stringify(state, null, 2));
    }
    chunks.push({ start: range.start, transcription: output.transcription });
    console.log(JSON.stringify({ chunk: range.index + 1, total: chunkRanges(state.duration).length, reused }));
  }
  const limit = Math.round(state.duration * 1000);
  const segments = mergeSegments(chunks).filter(row => row.from < limit).map(row => ({ ...row, to: Math.min(limit, row.to) }));
  const output = await resolveInside(root, job.outputDir);
  await atomic(join(output, 'transcript.raw.json'), JSON.stringify({ engine: 'whisper.cpp', model: runtime.model, language: 'ko', duration: state.duration, segments }, null, 2));
  const stamp = ms => new Date(ms).toISOString().slice(11, 23);
  const text = `# ${job.subject} · ${job.title} · 전사 초안\n\nWhisper.cpp / ko. 원음 및 GPT 대조 미완료.\n\n` + segments.map(row => `[${stamp(row.from)}–${stamp(row.to)}] ${row.text}`).join('\n\n');
  await atomic(join(output, 'transcript.md'), text + '\n');
  state.complete = true; await atomic(join(work, 'state.json'), JSON.stringify(state, null, 2));
  return { segments: segments.length, duration: state.duration, validation: 'draft-not-audio-verified' };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [root, key] = process.argv.slice(2);
  try {
    const runtime = JSON.parse(await readFile(new URL('../config/runtime.local.json', import.meta.url), 'utf8'));
    console.log(JSON.stringify(await transcribeJob(root, key, runtime)));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
