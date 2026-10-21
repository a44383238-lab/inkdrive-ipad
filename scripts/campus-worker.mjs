// Native parent sends cookies through an anonymous stdin pipe, never a file/argument/log.
import { SchoolHTTP,syncCampus } from '../shared/campus.mjs';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
let raw='';for await(const chunk of process.stdin){raw+=chunk;if(raw.length>4_000_000)throw new Error('input limit');}
let client;
try {
  const input=JSON.parse(raw);raw='';client=new SchoolHTTP(input.cookies);input.cookies=null;
  const onAttachment=relative=>!relative.toLowerCase().endsWith('.pptx')||process.platform!=='win32'?Promise.resolve():new Promise((resolve,reject)=>{
    const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-File',fileURLToPath(new URL('./preview-pptx.ps1',import.meta.url)),'-Root',input.root,'-Relative',relative],{windowsHide:true,stdio:'ignore'});
    child.once('error',reject);child.once('close',code=>code===0?resolve():reject(new Error('preview pending')));
  });
  const result=await syncCampus({root:input.root,client,deviceId:input.deviceId,manual:input.manual,onAttachment});
  process.stdout.write(JSON.stringify({ok:true,result,cookies:client.cookies}));
}catch(error){
  const known=/^(학교 |자료 대신 |자료 크기 제한|빈 자료|기존 자료를 )/.test(error.message)?error.message:'학교 연결이나 서재 접근을 확인해 주세요.';
  const code=String(error.code??error.cause?.code??'').replace(/[^A-Z0-9_]/g,'').slice(0,40);
  process.stdout.write(JSON.stringify({ok:false,message:known+(code?' ('+code+')':''),stage:client?.stage}));process.exitCode=1;
}
