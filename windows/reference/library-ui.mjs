let path='';const el=id=>document.getElementById(id);
async function refresh(){
  const response=await fetch('/api/library?path='+encodeURIComponent(path));
  if(!response.ok){el('status').textContent='상단의 폴더 연결을 눌러 주세요.';return;}
  const entries=await response.json();el('files').replaceChildren();el('where').textContent=path||'InkDrive';el('up').disabled=!path;
  for(const entry of entries){const button=document.createElement('button');button.className='file';const icon=document.createElement('span');icon.textContent=entry.directory?'▰':'▤';icon.className='file-icon';const name=document.createElement('span');name.textContent=entry.name;button.append(icon,name);button.onclick=()=>{if(entry.directory){path=entry.path;refresh();}else if(/\.(pdf|pptx)$/i.test(entry.path))location.href='/?path='+encodeURIComponent(entry.path);else el('status').textContent='원본은 보관돼 있어요. 해당 형식의 앱에서 열어 주세요.';};el('files').append(button);}
  el('status').textContent=entries.length?'':'비어 있어요';
}
el('up').onclick=()=>{path=path.split('/').slice(0,-1).join('/');refresh();};refresh().catch(()=>el('status').textContent='서재를 확인해 주세요.');
