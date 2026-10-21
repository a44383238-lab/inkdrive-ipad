// Native parent sends cookies through an anonymous stdin pipe, never a file/argument/log.
import { SchoolHTTP,syncCampus } from '../shared/campus.mjs';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
let raw='';for await(const chunk of process.stdin){raw+=chunk;if(raw.length>4_000_000)throw new Error('input limit');}
try {
  const input=JSON.parse(raw);raw='';const client=new SchoolHTTP(input.cookies);input.cookies=null;
  const onAttachment=relative=>!relative.toLowerCase().endsWith('.pptx')||process.platform!=='win32'?Promise.resolve():new Promise((resolve,reject)=>{
    const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-File',fileURLToPath(new URL('./preview-pptx.ps1',import.meta.url)),'-Root',input.root,'-Relative',relative],{windowsHide:true,stdio:'ignore'});
    child.once('error',reject);child.once('close',code=>code===0?resolve():reject(new Error('preview pending')));
  });
  const result=await syncCampus({root:input.root,client,deviceId:input.deviceId,manual:input.manual,onAttachment});
  process.stdout.write(JSON.stringify({ok:true,result,cookies:client.cookies}));
}catch{process.stdout.write(JSON.stringify({ok:false,message:'학교 로그인·네트워크·서재 접근을 확인해 주세요. 저장된 자료는 유지돼요.'}));process.exitCode=1;}
