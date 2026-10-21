import { readFile, mkdir, writeFile, rename, stat } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { dirname, extname } from 'node:path';
import { resolveInside } from '../scripts/daily-handoff.mjs';
import {portalTimetable} from './portal.mjs';
import {setTimeout as delay} from 'node:timers/promises';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export const schoolHosts = new Set(['plato.pusan.ac.kr','onestop.pusan.ac.kr','login.pusan.ac.kr']);
export function schoolURL(value, base = 'https://plato.pusan.ac.kr/') {
  const url = new URL(value.replaceAll('&amp;','&'),base);
  if (url.protocol !== 'https:' || !schoolHosts.has(url.hostname) || url.port || url.username || url.password) throw new Error('학교 외부 주소는 수집하지 않아요.');
  return url;
}
export const text = html => html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi,'').replace(/<[^>]*>/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&nbsp;/g,' ').replace(/\s+/g,' ').trim();
export function safeName(value) {
  const name = value.normalize('NFC').replace(/[<>:"/\\|?*\x00-\x1f]/g,'_').slice(0,90).replace(/[ .]+$/,'').trim();
  return !name || /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(name) || /^\.+$/.test(name) ? '자료_'+hash(value).slice(0,10) : name;
}
export function courseIdentity(course) {
  const match = /\b(20\d{2}-\d{4}),\s*([A-Za-z0-9]+_[A-Za-z0-9]+)/.exec(course.shortname ?? '');
  return match ? {term:match[1],code:match[2]} : null;
}
export function resources(html) {
  const seen = new Set(), result = [];
  for (const match of html.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    let url; try { url = schoolURL(match[1]); } catch { continue; }
    const kind = /^\/mod\/(ubfile|resource|assign|folder|url|page|forum)\/view\.php$/.exec(url.pathname)?.[1], id = url.searchParams.get('id');
    if (url.hostname !== 'plato.pusan.ac.kr' || !kind || !/^\d+$/.test(id) || seen.has(kind+id)) continue;
    seen.add(kind+id); result.push({ id,kind,title:text(match[2]).slice(0,120),url:url.href });
  }
  return result;
}
export function pluginFiles(html) {
  return [...new Set([...html.matchAll(/(?:href|src)=["']([^"']*pluginfile\.php[^"']*)["']/gi)].flatMap(m => {
    try { const url = schoolURL(m[1]); return url.hostname === 'plato.pusan.ac.kr' && !/\/(?:user\/icon|course\/overviewfiles|core_admin|theme_[^/]+)\//i.test(url.pathname) ? [url.href] : []; } catch { return []; }
  }))];
}
export function attachmentName(disposition, fallback) {
  const encoded=/filename\*=UTF-8''([^;]+)/i.exec(disposition)?.[1];
  let name;try{name=encoded?decodeURIComponent(encoded):/filename="([^"]+)"/i.exec(disposition)?.[1] ?? /filename=([^;]+)/i.exec(disposition)?.[1]?.trim();}catch{}
  if(name && [...name].every(c=>c.charCodeAt(0)<=255)) {
    try { name=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.from(name,'latin1')); } catch {}
  }
  name=name||fallback; const extension=/\.[A-Za-z0-9]{1,12}$/.exec(name)?.[0]??'';
  return safeName(extension?name.slice(0,-extension.length):name)+extension;
}
async function atomic(root, relative, bytes) {
  const path = await resolveInside(root,relative,true); await mkdir(dirname(path),{recursive:true});
  const temp = path+'.'+randomUUID()+'.partial'; await writeFile(temp,bytes,{flag:'wx'});
  // iCloud/Defender briefly locks the destination during hydration and metadata indexing.
  for(let attempt=0;;attempt++) {
    try { await rename(temp,path);break; }
    catch(error){if(attempt>=7||!['EPERM','EACCES','EBUSY'].includes(error.code))throw error;await delay(Math.min(800,100*2**attempt));}
  }
}
export class SchoolHTTP {
  constructor(cookies, transport = fetch) { this.cookies = cookies; this.transport = transport; }
  async request(value, options = {}, hops = 0) {
    const url = schoolURL(value); if (hops > 6) throw new Error('학교 로그인 이동을 확인해 주세요.');
    const cookies = this.cookies.filter(c => {
      const domain = (c.domain ?? c.Domain ?? '').replace(/^\./,'').toLowerCase();
      const expiry = c.expires ?? c.Expires;
      const path=c.path??c.Path??'/';
      return (url.hostname === domain || url.hostname.endsWith('.'+domain)) && (url.pathname===path||url.pathname.startsWith(path.endsWith('/')?path:path+'/')) && (!expiry || Number(expiry) < 0 || Number(expiry)*1000 > Date.now());
    });
    const response = await this.transport(url,{...options,redirect:'manual',signal:AbortSignal.timeout(180000),headers:{...options.headers,Cookie:cookies.map(c=>`${c.name ?? c.Name}=${c.value ?? c.Value}`).join('; ')}});
    // Only explicit school redirects are followed; credentials are never sent to arbitrary file links.
    if (response.status >= 300 && response.status < 400) {
      const next = schoolURL(response.headers.get('location') ?? '',url);
      if (next.hostname === 'login.pusan.ac.kr' || next.pathname.includes('/login/')) throw new Error('학교 로그인이 필요해요.');
      return this.request(next.href,{method:'GET'},hops+1);
    }
    if (!response.ok) throw new Error(`학교 응답 ${response.status}`);
    // Keep rotated session cookies in process memory and return them to the native profile.
    for (const raw of response.headers.getSetCookie?.() ?? []) {
      const [pair,...attrs] = raw.split(';'), cut=pair.indexOf('='); if(cut<1) continue;
      const c={name:pair.slice(0,cut).trim(),value:pair.slice(cut+1),domain:url.hostname,path:url.pathname.slice(0,url.pathname.lastIndexOf('/'))||'/',secure:true,httpOnly:false};
      for(const attr of attrs){const [k,...v]=attr.trim().split('='); if(k.toLowerCase()==='domain')c.domain=v.join('='); if(k.toLowerCase()==='path')c.path=v.join('='); if(k.toLowerCase()==='httponly')c.httpOnly=true; if(k.toLowerCase()==='expires')c.expires=Date.parse(v.join('='))/1000; if(k.toLowerCase()==='max-age')c.expires=Date.now()/1000+Number(v.join('='));}
      const domain=c.domain.replace(/^\./,''); if(url.hostname!==domain && !url.hostname.endsWith('.'+domain))continue;
      this.cookies=this.cookies.filter(x=>!((x.name??x.Name)===c.name&&(x.domain??x.Domain)===c.domain&&(x.path??x.Path)===c.path));this.cookies.push(c);
    }
    return response;
  }
  async html(url) {
    const response=await this.request(url); const data=await response.text();
    if(data.length>15_000_000 || /name=["']loginform["']|id=["']loginbtn["']/i.test(data))throw new Error('학교 로그인이 필요해요.'); return data;
  }
}
export async function syncCampus({root,client,deviceId,manual=false,now=Date.now(),onAttachment=null}) {
  if(!/^[a-zA-Z0-9_-]{1,64}$/.test(deviceId))throw new Error('device identity');
  const statePath=`.inkdrive/campus/devices/${deviceId}.json`;
  let state;try{state=JSON.parse(await readFile(await resolveInside(root,statePath),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;state={courses:[],resources:{},attachments:{}};}
  const home=await client.html('https://plato.pusan.ac.kr/'), sesskey=/["']sesskey["']\s*:\s*["']([A-Za-z0-9]+)["']/.exec(home)?.[1];
  if(!sesskey)throw new Error('학교 로그인이 필요해요.');
  const response=await client.request(`https://plato.pusan.ac.kr/lib/ajax/service.php?sesskey=${sesskey}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([{index:0,methodname:'core_course_get_enrolled_courses_by_timeline_classification',args:{classification:'all',limit:0,offset:0,sort:'fullname'}}])});
  const envelope=await response.json(); if(!Array.isArray(envelope)||envelope[0]?.error||!Array.isArray(envelope[0]?.data?.courses))throw new Error('학교 수강목록을 읽지 못했어요.');
  state.courses=envelope[0].data.courses;
  if(state.courses.some(c=>!Number.isSafeInteger(c.id)||c.id<1))throw new Error('과목 식별자를 확인해 주세요.');
  const term=state.courses.map(courseIdentity).filter(Boolean).map(i=>i.term).sort().at(-1); let downloaded=0;state.failures=[];
  for(const course of state.courses.filter(c=>courseIdentity(c)?.term===term && term)) {
    client.stage={course:course.id};
    const info=courseIdentity(course),folder=`${info.term}/${safeName(course.fullname)}_${info.code}`;
    await atomic(root,`${folder}/.campus-course.json`,JSON.stringify(course));
    const items=resources(await client.html(`https://plato.pusan.ac.kr/course/view.php?id=${course.id}&mode=sections`)); state.resources[course.id]=items;
    for(const item of items) {
      client.stage={course:course.id,resource:item.id,kind:item.kind};
      try {
      let detail=null;
      if(item.kind==='url') {
        await atomic(root,`${folder}/일정/url_${item.id}.txt`,`${item.title}\n${item.url}`);continue;
      }
      if(['assign','url','page'].includes(item.kind)) {
        detail=await client.html(item.url);await atomic(root,`${folder}/일정/${item.kind}_${item.id}.txt`,text(detail));
      }
      if(item.kind!=='ubfile'&&detail===null)detail=await client.html(item.url);
      let urls=item.kind==='ubfile' ? [`https://plato.pusan.ac.kr/local/csmsdoc/download.php?id=${item.id}&tp=m&pg=ubfile`] : pluginFiles(detail);
      if(item.kind==='forum'){
        const discussions=[...new Set([...detail.matchAll(/\/mod\/forum\/discuss\.php\?d=(\d+)/g)].map(m=>m[1]))].slice(0,20);
        for(const id of discussions){const notice=await client.html(`https://plato.pusan.ac.kr/mod/forum/discuss.php?d=${id}`);urls.push(...pluginFiles(notice));await atomic(root,`${folder}/일정/notice_${id}.txt`,text(notice));}
      }
      urls=[...new Set(urls)];
      for(const url of urls) {
        if(/\.(mp4|mov|m3u8|mpd|webm)$/i.test(new URL(url).pathname))continue;
        const key=`${info.term}/${course.id}/${item.kind}/${item.id}/${hash(url)}`,old=state.attachments[key];
        if(!manual&&old&&now-Date.parse(old.checked)<86400000)continue;
        const response=await client.request(url,{headers:{Referer:item.url}});
        if((Number(response.headers.get('content-length'))||0)>256_000_000 || (response.headers.get('content-type')?.startsWith('text/html')&&!response.headers.get('content-disposition')?.includes('attachment')))throw new Error('자료 대신 로그인 화면이나 큰 파일이 도착했어요.');
        const chunks=[];let size=0;for await(const chunk of response.body){size+=chunk.length;if(size>256_000_000)throw new Error('자료 크기 제한');chunks.push(chunk);}
        const bytes=Buffer.concat(chunks);if(!bytes.length)throw new Error('빈 자료');const sha=hash(bytes);
        if(old?.sha256===sha){try{await stat(await resolveInside(root,old.path));state.attachments[key]={...old,checked:new Date(now).toISOString()};continue;}catch(e){if(e.code!=='ENOENT')throw e;}}
        const name=attachmentName(response.headers.get('content-disposition')??'',new URL(url).pathname.split('/').at(-1)||item.title),ext=extname(name),base=name.slice(0,name.length-ext.length);
        const relative=`${folder}/강의자료/${base}__${item.id}__${sha.slice(0,12)}${ext}`;
        try{const existing=await readFile(await resolveInside(root,relative));if(hash(existing)!==sha)throw new Error('기존 자료를 덮어쓰지 않았어요.');}catch(e){if(e.code!=='ENOENT')throw e;await atomic(root,relative,bytes);}
        state.attachments[key]={sha256:sha,path:relative,checked:new Date(now).toISOString()};downloaded++;
        await atomic(root,statePath,JSON.stringify(state,null,2));
        if(onAttachment)try{await onAttachment(relative);}catch{state.previewStatus='일부 미리보기 생성 대기';}
      }
      } catch(error) {
        if(/로그인/.test(error.message)||['EACCES','EPERM','ENOSPC'].includes(error.code))throw error;
        state.failures.push({course:course.id,resource:item.id,kind:item.kind});
      }
    }
  }
  try {
    if(term){const rows=await portalTimetable(client,term);await atomic(root,'.inkdrive/campus/timetable-api.json',JSON.stringify(rows,null,2));}
  }catch{state.timetableStatus='학지시 로그인 또는 시간표 응답 확인 필요';}
  try {
    const portal=await client.html('https://onestop.pusan.ac.kr/main');
    const rows=[...portal.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)].filter(m=>m[1].includes('schedule-item')).map(m=>text(m[1]));
    if(rows.length)await atomic(root,'.inkdrive/campus/timetable.json',JSON.stringify(rows));
  }catch{state.timetableStatus='학지시 로그인 확인 필요';}
  state.lastAttempt=new Date(now).toISOString();if(!state.failures.length)state.lastChecked=state.lastAttempt;
  await atomic(root,statePath,JSON.stringify(state,null,2));return {downloaded,courses:state.courses.length,lastChecked:state.lastChecked,failed:state.failures.length};
}
