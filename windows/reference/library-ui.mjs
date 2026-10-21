let path='';const el=id=>document.getElementById(id);
function folderTitle(name){
  const term=/^(20\d{2})-(0010|0020)$/.exec(name);
  return term?`${term[1]} · ${term[2]==='0010'?'1학기':'2학기'}`:name.replace(/_[A-Z]{2}\d+_(\d{3})$/,' ($1)');
}
function fileIcon(directory){
  const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');svg.setAttribute('viewBox','0 0 96 80');svg.setAttribute('aria-hidden','true');svg.classList.add('file-icon');
  const shape=(d,fill,stroke)=>{const p=document.createElementNS(ns,'path');p.setAttribute('d',d);p.setAttribute('fill',fill);if(stroke){p.setAttribute('stroke',stroke);p.setAttribute('stroke-width','2');}svg.append(p);};
  if(directory){shape('M8 21Q8 15 14 15H35L44 23H82Q88 23 88 29V65Q88 71 82 71H14Q8 71 8 65Z','#abc4ee');shape('M8 34Q8 28 14 28H82Q88 28 88 34V65Q88 71 82 71H14Q8 71 8 65Z','#7297d5');shape('M17 39H79','none','#94b2e2');}
  else{shape('M27 5H59L73 19V72H27Z','#f4f7fc','#a8bbd9');shape('M59 5V20H73','none','#a8bbd9');shape('M37 34H63M37 45H63M37 56H56','none','#8da9d1');}
  return svg;
}
async function refresh(){
  const response=await fetch('/api/library?path='+encodeURIComponent(path));
  if(!response.ok){el('status').textContent='상단의 폴더 연결을 눌러 주세요.';return;}
  const entries=await response.json();el('files').replaceChildren();el('where').textContent=path?path.split('/').map(folderTitle).join(' / '):'InkDrive';el('up').disabled=!path;
  for(const entry of entries){const button=document.createElement('button');button.className='file';const name=document.createElement('span');name.textContent=entry.directory?folderTitle(entry.name):entry.name;button.append(fileIcon(entry.directory),name);button.onclick=()=>{if(entry.directory){path=entry.path;refresh();}else if(/\.(pdf|pptx)$/i.test(entry.path))location.href='/?path='+encodeURIComponent(entry.path);else el('status').textContent='원본은 보관돼 있어요. 해당 형식의 앱에서 열어 주세요.';};el('files').append(button);}
  el('status').textContent=entries.length?'':'비어 있어요';
}
el('up').onclick=()=>{path=path.split('/').slice(0,-1).join('/');refresh();};refresh().catch(()=>el('status').textContent='서재를 확인해 주세요.');
