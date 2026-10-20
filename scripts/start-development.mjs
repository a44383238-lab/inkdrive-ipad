import { spawn } from 'node:child_process';
import { mkdir, open } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const page = process.argv[2];
async function running() {
  try { return (await (await fetch('http://127.0.0.1:8081/status', { signal: AbortSignal.timeout(1000) })).text()).includes('packager-status:running'); }
  catch { return false; }
}
if (!await running()) {
  await mkdir(join(root, '.expo'), { recursive: true });
  const log = await open(join(root, '.expo', 'development-server.log'), 'a');
  const child = spawn(process.execPath, ['node_modules/expo/bin/cli', 'start', '--dev-client', '--lan', '--port', '8081'], {
    cwd: root, detached: true, windowsHide: true, stdio: ['ignore', log.fd, log.fd], env: { ...process.env, CI: '1' },
  });
  child.unref(); await log.close();
  for (let attempt = 0; attempt < 50 && !await running(); attempt++) await new Promise(resolve => setTimeout(resolve, 300));
  if (!await running()) throw new Error('개발 서버를 시작하지 못했어요. .expo/development-server.log를 확인해 주세요.');
}
if (page) {
  const viewer = spawn('explorer.exe', [resolve(page)], { detached: true, windowsHide: true, stdio: 'ignore' });
  viewer.unref();
}
