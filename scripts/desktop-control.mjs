import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { configuredRunner, recentDates } from './desktop-runner.mjs';

const port = 8769;
function html(token) {
  return String.raw`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="inkdrive-token" content="${token}"><title>InkDrive 수업 정리</title>
<style nonce="${token}">*{box-sizing:border-box}body{margin:0;background:#f4f6fb;color:#20304b;font:16px/1.7 -apple-system,BlinkMacSystemFont,'Malgun Gothic',sans-serif}main{max-width:950px;margin:50px auto;padding:0 24px}.top{display:flex;justify-content:space-between;align-items:center}.brand{font-size:27px;font-weight:850;letter-spacing:-1px}.brand span{color:#2455d6}.badge{font-size:12px;color:#536b8d;background:#e7edf9;padding:7px 14px;border-radius:20px}.eyebrow{font-size:11px;letter-spacing:2px;color:#6d80a0;margin-top:52px}h1{font-size:36px;letter-spacing:-1px;line-height:1.4;margin:12px 0}.muted{color:#6b7d97}.card{background:white;border:1px solid #dfe6f1;border-radius:18px;padding:30px;margin:28px 0;box-shadow:0 8px 28px #243b6310}.row{display:flex;align-items:center;gap:12px;flex-wrap:wrap}input[type=date]{font:inherit;border:1px solid #d5dfef;padding:8px 12px;border-radius:8px;color:#304c74}button{font:inherit;cursor:pointer;border:0;border-radius:10px;padding:13px 22px;color:white;background:#2455d6;font-weight:700;min-height:48px}button:disabled{opacity:.5;cursor:wait}button:hover:enabled{filter:brightness(.96)}button.secondary{color:#435e83;background:#edf2fa}.status{margin-top:28px;padding-top:23px;border-top:1px solid #e7ecf5}.status h2{font-size:19px;margin:0}.small{font-size:13px;color:#71829b}.counts{display:flex;gap:12px;margin:18px 0}.count{padding:10px 16px;border-radius:9px;background:#f0f4fb}.error{color:#b73c3c;white-space:pre-wrap}.flow{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}.step{flex:1;min-width:150px;background:#eef3fc;border-radius:12px;padding:18px}.step b{color:#587fc4;font-size:12px}.step strong{display:block;font-size:15px}.footer{font-size:12px;color:#7c8ba1;margin:24px 0 40px}a{color:#2455d6}@media(max-width:600px){main{margin-top:24px}.badge{display:none}h1{font-size:27px}.card{padding:22px}.eyebrow{margin-top:30px}.step{min-width:100%}}</style>
<main><div class="top"><div class="brand">InkDrive<span>.</span></div><div class="badge">이 노트북에서 실행 · iCloud 원본 사용</div></div>
<div class="eyebrow">YOUR EVENING STUDY ROUTINE</div><h1>오늘의 수업을,<br>다시 내 것으로.</h1><p class="muted">예약을 놓쳤다면 지금 시작하세요. 이미 정리한 수업은 건너뛰어요.</p>
<section class="card"><div class="row"><input id="date" type="date" aria-label="수업 날짜"><label class="small"><input id="catchup" type="checkbox" checked> 최근 7일의 미처리 수업도 확인</label></div>
<div class="row" style="margin-top:20px"><button id="run">지금 수업 정리</button><button id="open" class="secondary">결과 폴더 열기</button></div>
<div class="status" aria-live="polite"><h2 id="phase">준비 중</h2><div id="message" class="muted"></div><div id="current" class="small"></div>
<div class="counts"><div class="count">완료 <strong id="completed">0</strong></div><div class="count">실패 <strong id="failed">0</strong></div><div class="count">대기 <strong id="blocked">0</strong></div></div><div id="detail" class="error"></div><div id="root" class="small"></div></div></section>
<div class="flow"><div class="step"><b>01</b><strong>녹음 전사</strong><span class="small">한국어 · 분할 처리 · 재개</span></div><div class="step"><b>02</b><strong>상세 강의노트</strong><span class="small">필기 PDF와 대조</span></div><div class="step"><b>03</b><strong>복습문제와 해설</strong><span class="small">문제·정답을 나눠 저장</span></div></div>
<p class="footer">밤 10시 예약은 Codex 앱이 켜져 있어야 해요. 이 수동 버튼은 로그인된 로컬 실행기를 사용해요.<br>원본은 iCloud에 유지해요. 별도 유료 AI API나 Google Drive는 사용하지 않아요. 창을 닫아도 시작한 작업은 실행기가 켜져 있는 동안 계속돼요.</p></main>
<script nonce="${token}">const token=document.querySelector('meta[name=inkdrive-token]').content;const el=id=>document.getElementById(id);el('date').value=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul'}).format(new Date());const labels={idle:'준비됨',scanning:'수업 자료 확인 중',processing:'수업 정리 중',transcribing:'녹음 전사 중',writing:'강의노트·복습문제 작성 중',complete:'확인 완료',failed:'확인이 필요한 항목이 있어요',waiting:'자료 동기화·수업 종료 대기'};async function status(){try{const s=await(await fetch('/api/status')).json();el('phase').textContent=labels[s.phase]||s.phase;el('message').textContent=s.message;el('current').textContent=s.current||'';el('completed').textContent=s.completed;el('failed').textContent=s.failed;el('blocked').textContent=s.blocked.length;el('root').textContent=s.root;el('run').disabled=s.running;el('detail').textContent=[...(s.errors||[]).map(x=>x.lesson+': '+x.message),...s.blocked.map(x=>x.manifest+': '+x.reason)].join('\n');}catch{el('message').textContent='실행기 연결이 끊겼어요. 바탕화면의 수업 정리를 다시 열어 주세요.';}}async function post(path,body={}){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-InkDrive-Token':token},body:JSON.stringify(body)});if(!r.ok)throw new Error(await r.text());}el('run').onclick=async()=>{el('run').disabled=true;try{await post('/api/run',{date:el('date').value,catchup:el('catchup').checked});await status();}catch(e){el('detail').textContent=e.message;el('run').disabled=false;}};el('open').onclick=()=>post('/api/open-results').catch(e=>el('detail').textContent=e.message);status();setInterval(status,2000);</script></html>`;
}
export function createControlServer(runner) {
  const token = randomBytes(24).toString('hex');
  const server = http.createServer(async (request, response) => {
    const expected = `127.0.0.1:${server.address().port}`;
    const allowedHost = request.headers.host === expected || request.headers.host === `localhost:${server.address().port}`;
    const allowedOrigin = !request.headers.origin || [`http://${expected}`, `http://localhost:${server.address().port}`].includes(request.headers.origin);
    response.setHeader('Cache-Control', 'no-store'); response.setHeader('X-Content-Type-Options', 'nosniff');
    const json = (code, value) => { response.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' }); response.end(JSON.stringify(value)); };
    if (!allowedHost || !allowedOrigin) { json(403, { error: '허용되지 않은 요청이에요.' }); return; }
    if (request.method === 'GET' && request.url === '/') {
      response.setHeader('Content-Security-Policy', `default-src 'self'; script-src 'nonce-${token}'; style-src 'nonce-${token}'; connect-src 'self'; frame-ancestors 'none'`);
      response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); response.end(html(token)); return;
    }
    if (request.method === 'GET' && request.url === '/api/status') { json(200, { ...runner.state, root: runner.root, service: 'inkdrive-control' }); return; }
    if (request.method !== 'POST' || request.headers['x-inkdrive-token'] !== token) { json(403, { error: '버튼을 실행 창에서 다시 눌러 주세요.' }); return; }
    try {
      let body = ''; for await (const chunk of request) { body += chunk; if (body.length > 2048) throw new Error('요청이 너무 커요.'); }
      const input = JSON.parse(body || '{}');
      if (request.url === '/api/run') {
        const dates = recentDates(input.date, input.catchup === false ? 1 : 7);
        void runner.run(dates).catch(error => runner.update({ phase: 'failed', running: false, message: error.message }));
        json(202, { accepted: true }); return;
      }
      if (request.url === '/api/open-results') {
        const folder = join(runner.root, 'AI'); await mkdir(folder, { recursive: true });
        if (process.platform === 'win32') spawn('explorer.exe', [folder], { windowsHide: true, detached: true, stdio: 'ignore' }).unref();
        json(200, { folder }); return;
      }
      json(404, { error: '알 수 없는 작업이에요.' });
    } catch (error) { json(400, { error: error.message }); }
  });
  return server;
}
async function openWindow() {
  const url = `http://127.0.0.1:${port}`;
  const healthy = async () => {
    try { return (await (await fetch(url + '/api/status', { signal: AbortSignal.timeout(800) })).json()).service === 'inkdrive-control'; } catch { return false; }
  };
  if (!await healthy()) {
    const child = spawn(process.execPath, [fileURLToPath(import.meta.url)], { detached: true, windowsHide: true, stdio: 'ignore' }); child.unref();
    for (let index = 0; index < 25 && !await healthy(); index++) await new Promise(resolve => setTimeout(resolve, 200));
  }
  if (!await healthy()) throw new Error('수업 정리 창을 시작하지 못했어요. 포트 8769를 확인해 주세요.');
  if (process.platform === 'win32') spawn('powershell.exe', ['-NoProfile', '-Command', `Start-Process '${url}'`], { windowsHide: true, stdio: 'ignore' }).unref();
  console.log(url);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--open')) await openWindow();
  else {
    const runner = await configuredRunner();
    const server = createControlServer(runner);
    server.listen(port, '127.0.0.1', () => console.log(`InkDrive control http://127.0.0.1:${port}`));
  }
}
