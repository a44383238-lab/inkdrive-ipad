const date=document.getElementById('date'),list=document.getElementById('lessons');date.value=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul'}).format(new Date());
async function refresh(){const r=await fetch('/api/lessons?date='+date.value);if(!r.ok)throw new Error('폴더 연결을 확인해 주세요.');list.replaceChildren();for(const lesson of await r.json()){
  const card=document.createElement('article'),title=document.createElement('h2');title.textContent=lesson.subject+' · '+lesson.title;card.append(title);
  const link=document.createElement('a');link.textContent='필기 열기';link.href='/?path='+encodeURIComponent(lesson.pdf);card.append(link);
  for(const path of lesson.recordings){const row=document.createElement('div'),label=document.createElement('p'),audio=document.createElement('audio');label.textContent=path.split('/').at(-1);audio.controls=true;audio.preload='none';audio.src='/api/audio?path='+encodeURIComponent(path);row.append(label,audio);card.append(row);}list.append(card);
}document.getElementById('status').textContent=list.children.length?'':'수업 없음';}date.onchange=()=>refresh().catch(e=>document.getElementById('status').textContent=e.message);date.onchange();
