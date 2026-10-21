import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile,readdir,realpath,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SchoolHTTP,syncCampus,resources,pluginFiles,courseIdentity,safeName,text,attachmentName} from '../shared/campus.mjs';

test('school metadata retains term and section; external links and traversal names are excluded',()=>{
  assert.deepEqual(courseIdentity({shortname:'통계 (2026-0020, IE2400211_066)'}),{term:'2026-0020',code:'IE2400211_066'});
  const html=`<a href="/mod/ubfile/view.php?id=3&amp;x=2"><span>자료</span></a><a href="https://evil.test/mod/ubfile/view.php?id=4">bad</a><a href="/mod/assign/view.php?id=7">과제</a>`;
  assert.deepEqual(resources(html).map(x=>x.id),['3','7']);assert.equal(resources(html)[0].title,'자료');
  assert.deepEqual(pluginFiles(`<a href="https://evil.test/pluginfile.php/a.pdf">bad</a>`),[]);
  assert.doesNotMatch(safeName('../../CON.pdf'),/[\\/]/);assert.notEqual(safeName('CON.pdf'),'CON.pdf');
});
test('school filenames decode UTF-8 headers and keep the extension of long Korean names; decorative icons are excluded',()=>{
  const name='공학작문및발표_조사보고서.pdf';
  assert.equal(attachmentName(`attachment; filename="${Buffer.from(name).toString('latin1')}"`,'x'),name);
  assert.equal(attachmentName(`attachment; filename*=UTF-8''${encodeURIComponent(name)}`,'x'),name);
  assert.match(attachmentName(`attachment; filename="${'과제'.repeat(80)}.pdf"`,'x'),/\.pdf$/);
  assert.deepEqual(pluginFiles(`<img src='/pluginfile.php/1/user/icon/f1.jpg'><a href='/pluginfile.php/2/theme_coursemos/favicon/1/favicon.ico'>icon</a><a href='/pluginfile.php/3/mod_assign/introattachment/0/과제.pdf'>자료</a>`),['https://plato.pusan.ac.kr/pluginfile.php/3/mod_assign/introattachment/0/%EA%B3%BC%EC%A0%9C.pdf']);
});
test('HTTP session restricts cookie domains and refuses external redirects',async()=>{
  let sent;const client=new SchoolHTTP([{name:'secret',value:'private',domain:'plato.pusan.ac.kr',path:'/'},{name:'portal',value:'other',domain:'onestop.pusan.ac.kr',path:'/'}],async(url,options)=>{sent=options.headers.Cookie;return new Response(null,{status:302,headers:{location:'https://evil.test/steal'}});});
  await assert.rejects(client.request('https://plato.pusan.ac.kr/'),/외부/);assert.equal(sent,'secret=private');
  await assert.rejects(client.request('http://plato.pusan.ac.kr/'),/외부/);
});
test('recurring sync skips unchanged files, preserves annotated originals and creates a new revision',async t=>{
  const root=await realpath(await mkdtemp(join(tmpdir(),'inkdrive-campus-')));t.after(()=>rm(root,{recursive:true,force:true}));
  let revision=1,term='2026-0020',downloads=0;
  const client={html:async url=>url.endsWith('.kr/')?`{"sesskey":"ephemeral"}`:url.includes('/course/')?`<a href="/mod/ubfile/view.php?id=3">자료</a>`:'<tr><td>09:00</td><td><a href="#schedule-itemIE1">통계</a></td></tr>',
    request:async url=>url.includes('/lib/ajax/')?Response.json([{error:false,data:{courses:[{id:2,fullname:'통계',shortname:`통계 (${term}, IE1_066)`}]}}]):(downloads++,new Response(Buffer.from('%PDF-'+revision),{headers:{'Content-Type':'application/pdf','Content-Disposition':'attachment; filename="lecture.pdf"'}}))};
  const options={root,client,deviceId:'test-device',now:Date.parse('2026-10-21T10:00:00Z')};
  assert.equal((await syncCampus(options)).downloaded,1);assert.equal((await syncCampus(options)).downloaded,0);assert.equal(downloads,1);
  const folder=join(root,'2026-0020','통계_IE1_066','강의자료'),original=join(folder,(await readdir(folder))[0]);
  await writeFile(original,'%PDF-annotated locally');revision=2;
  assert.equal((await syncCampus({...options,manual:true})).downloaded,1);assert.equal(await readFile(original,'utf8'),'%PDF-annotated locally');assert.equal((await readdir(folder)).length,2);
  term='2027-0010';assert.equal((await syncCampus({...options,manual:true})).downloaded,1);
  assert.equal((await readdir(join(root,'2027-0010','통계_IE1_066','강의자료'))).length,1);
  assert.equal(await readFile(original,'utf8'),'%PDF-annotated locally');
});
test('expired login and interrupted download do not produce completed records',async t=>{
  const root=await mkdtemp(join(tmpdir(),'inkdrive-campus-fail-'));t.after(()=>rm(root,{recursive:true,force:true}));
  await assert.rejects(syncCampus({root,client:{html:async()=>'<form name="loginform"></form>'},deviceId:'test'}),/로그인/);
  assert.deepEqual(await readdir(root),[]);
});
test('assignment and notice attachments are collected while scripts and session values are excluded from saved text',async t=>{
  const root=await mkdtemp(join(tmpdir(),'inkdrive-notices-'));t.after(()=>rm(root,{recursive:true,force:true}));
  const client={html:async url=>{
    if(url==='https://plato.pusan.ac.kr/')return `{"sesskey":"memoryonly"}`;
    if(url.includes('/course/'))return `<a href='/mod/url/view.php?id=6'>외부 수업 링크</a><a href='/mod/assign/view.php?id=7'>과제</a><a href='/mod/forum/view.php?id=9'>공지</a>`;
    if(url.includes('/mod/url/'))throw new Error('external target must not receive the school session');
    if(url.includes('/assign/'))return `<h1>과제 11월 3일</h1><script>M.cfg={sesskey:'must-not-persist'}</script><a href='/pluginfile.php/7/assignment.pdf'>첨부</a>`;
    if(url.includes('/forum/view'))return `<a href='/mod/forum/discuss.php?d=11'>공지</a>`;
    if(url.includes('/forum/discuss'))return `<h1>수업자료</h1><script>token='must-not-persist'</script><a href='/pluginfile.php/11/notice.pdf'>첨부</a>`;
    return '';
  },request:async url=>url.includes('/lib/ajax/')?Response.json([{error:false,data:{courses:[{id:2,fullname:'통계',shortname:'통계 (2026-0020, IE1_066)'}]}}]):new Response('%PDF-fixture',{headers:{'Content-Type':'application/pdf'}})};
  assert.equal((await syncCampus({root,client,deviceId:'test'})).downloaded,2);
  const folder=join(root,'2026-0020','통계_IE1_066');assert.equal((await readdir(join(folder,'강의자료'))).length,2);
  for(const name of ['assign_7.txt','notice_11.txt'])assert.doesNotMatch(await readFile(join(folder,'일정',name),'utf8'),/must-not-persist|sesskey|token/);
  assert.match(await readFile(join(folder,'일정','url_6.txt'),'utf8'),/https:\/\/plato\.pusan\.ac\.kr\/mod\/url\/view\.php\?id=6/);
  assert.equal(text('<h1>내용</h1><style>private</style><script>private</script>'),'내용');
});
test('download interrupted before completion never publishes an attachment or a successful sync timestamp',async t=>{
  const root=await mkdtemp(join(tmpdir(),'inkdrive-partial-'));t.after(()=>rm(root,{recursive:true,force:true}));
  const client={html:async url=>url.endsWith('.kr/')?`{"sesskey":"memory"}`:`<a href='/mod/ubfile/view.php?id=3'>자료</a>`,request:async url=>url.includes('/lib/ajax/')?Response.json([{error:false,data:{courses:[{id:2,fullname:'통계',shortname:'통계 (2026-0020, IE1_066)'}]}}]):new Response(new ReadableStream({start(controller){controller.enqueue(new Uint8Array([1,2]));controller.error(new Error('network interrupted'));}}),{headers:{'Content-Type':'application/pdf'}})};
  assert.equal((await syncCampus({root,client,deviceId:'test'})).failed,1);
  const state=JSON.parse(await readFile(join(root,'.inkdrive','campus','devices','test.json'),'utf8'));assert.equal(state.lastChecked,undefined);assert.deepEqual(state.attachments,{});
  assert.deepEqual(await readdir(join(root,'2026-0020','통계_IE1_066')),['.campus-course.json']);
});
