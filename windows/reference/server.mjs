import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makePDF, makeInk } from './fixture.mjs';
import { validateInk } from '../../shared/ink-format.mjs';
import { LibraryReader } from './library.mjs';
import { resolveInside } from '../../scripts/daily-handoff.mjs';
import { readdir,stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';

const here = dirname(fileURLToPath(import.meta.url));
export function createReferenceServer({root=null,cache=null}={}) {
  const library=root?new LibraryReader(root,{cache}):null;
  const pdf = makePDF(), ink = validateInk(makeInk(pdf));
  return http.createServer(async (req, res) => {
    const host = `127.0.0.1:${res.socket.localPort}`;
    if (req.headers.host !== host || req.method !== 'GET') { res.writeHead(403); res.end(); return; }
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; worker-src 'self' blob:; img-src 'self' blob: data:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'");
    const routes = { '/': ['index.html', 'text/html'], '/viewer.mjs': ['viewer.mjs', 'text/javascript'], '/viewer.css': ['viewer.css', 'text/css'],
      '/ink-format.mjs': ['../../shared/ink-format.mjs', 'text/javascript'],
      '/pdf.mjs': ['node_modules/pdfjs-dist/build/pdf.mjs', 'text/javascript'],
      '/pdf.worker.mjs': ['node_modules/pdfjs-dist/build/pdf.worker.mjs', 'text/javascript'] };
    try {
      const url = new URL(req.url, `http://${host}`);
      if(library && url.pathname==='/api/lessons') {
        const date=url.searchParams.get('date');if(!/^\d{4}-\d{2}-\d{2}$/.test(date))throw new Error('date');
        let names=[];try{names=await readdir(await resolveInside(root,'.inkdrive/lessons'));}catch(e){if(e.code!=='ENOENT')throw e;}
        const lessons=[];for(const name of names.filter(n=>/^[0-9a-f-]{36}\.json$/i.test(n))){try{const value=JSON.parse(await readFile(await resolveInside(root,'.inkdrive/lessons/'+name),'utf8'));if(value.date===date&&Array.isArray(value.recordings))lessons.push(value);}catch{}}
        res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(lessons));return;
      }
      if(library && url.pathname==='/api/audio') {
        const relative=url.searchParams.get('path');if(!/\.(m4a|mp3|wav|aac|mp4|caf)$/i.test(relative))throw new Error('audio');
        const path=await resolveInside(root,relative),size=(await stat(path)).size;let start=0,end=size-1,code=200;
        if(req.headers.range){const m=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);if(!m){res.writeHead(416);res.end();return;}start=Number(m[1]);end=m[2]?Math.min(Number(m[2]),end):end;if(start>end){res.writeHead(416);res.end();return;}code=206;}
        res.writeHead(code,{'Content-Type':/\.mp3$/i.test(relative)?'audio/mpeg':/\.wav$/i.test(relative)?'audio/wav':'audio/mp4','Content-Length':end-start+1,'Accept-Ranges':'bytes',...(code===206?{'Content-Range':`bytes ${start}-${end}/${size}`}:{})});createReadStream(path,{start,end}).pipe(res);return;
      }
      if(library && url.pathname === '/api/library') { res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(await library.list(url.searchParams.get('path')??'')));return; }
      if(library && ['/api/document','/api/document-ink'].includes(url.pathname)) {
        const opened=await library.open(url.searchParams.get('path')??'');
        res.writeHead(200,{'Content-Type':url.pathname==='/api/document'?'application/pdf':'application/json'});
        res.end(url.pathname==='/api/document'?opened.pdf:JSON.stringify({ink:opened.ink,state:opened.state,heads:opened.heads}));return;
      }
      if(req.url==='/library') {res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});res.end(await readFile(join(here,'library.html')));return;}
      if(req.url==='/library-ui.mjs') {res.writeHead(200,{'Content-Type':'text/javascript'});res.end(await readFile(join(here,'library-ui.mjs')));return;}
      if(['/today','/today.mjs'].includes(req.url)){res.writeHead(200,{'Content-Type':req.url==='/today'?'text/html; charset=utf-8':'text/javascript'});res.end(await readFile(join(here,req.url==='/today'?'today.html':'today.mjs')));return;}
      if (req.url === '/fixture.pdf') { res.writeHead(200, { 'Content-Type': 'application/pdf', 'Content-Length': pdf.length }); res.end(pdf); return; }
      if (req.url === '/fixture.ink.json') { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(ink)); return; }
      const route = routes[url.pathname]; if (!route) { res.writeHead(404); res.end(); return; }
      const bytes = await readFile(resolve(here, route[0])); res.writeHead(200, { 'Content-Type': `${route[1]}; charset=utf-8` }); res.end(bytes);
    } catch { res.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end('참조 뷰어 구성 파일이 없어요. windows/reference에서 npm ci를 실행해 주세요.'); }
  });
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port=Number(process.env.INKDRIVE_PORT)||8770;
  const server = createReferenceServer({root:process.env.INKDRIVE_ROOT||null,cache:process.env.INKDRIVE_CACHE||null}); server.listen(port, '127.0.0.1');
}
