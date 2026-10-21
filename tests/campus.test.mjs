import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile,readdir,realpath,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SchoolHTTP,syncCampus,resources,pluginFiles,courseIdentity,safeName} from '../shared/campus.mjs';

test('school metadata retains term and section; external links and traversal names are excluded',()=>{
  assert.deepEqual(courseIdentity({shortname:'통계 (2026-0020, IE2400211_066)'}),{term:'2026-0020',code:'IE2400211_066'});
  const html=`<a href="/mod/ubfile/view.php?id=3&amp;x=2"><span>자료</span></a><a href="https://evil.test/mod/ubfile/view.php?id=4">bad</a><a href="/mod/assign/view.php?id=7">과제</a>`;
  assert.deepEqual(resources(html).map(x=>x.id),['3','7']);assert.equal(resources(html)[0].title,'자료');
  assert.deepEqual(pluginFiles(`<a href="https://evil.test/pluginfile.php/a.pdf">bad</a>`),[]);
  assert.doesNotMatch(safeName('../../CON.pdf'),/[\\/]/);assert.notEqual(safeName('CON.pdf'),'CON.pdf');
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
