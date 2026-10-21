import { readFile,readdir,stat,realpath,mkdir,writeFile,rename } from 'node:fs/promises';
import { createHash,randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { readLatest } from '../../shared/ink-commits.mjs';
import { validateInk } from '../../shared/ink-format.mjs';
import { resolveInside } from '../../scripts/daily-handoff.mjs';
const sha = b => createHash('sha256').update(b).digest('hex');
export class LibraryReader {
  constructor(root,{cache=null}={}) {this.root=root;this.cache=cache?join(cache,sha(root)):null;this.current=null;}
  async list(relative='') {
    const root=await realpath(this.root),folder=relative?await resolveInside(root,relative):root;
    const entries=[];for(const item of await readdir(folder,{withFileTypes:true})) {
      if(item.name.startsWith('.')||item.isSymbolicLink()||item.name.endsWith('.adapter.json'))continue;
      entries.push({name:item.name,path:relative?relative+'/'+item.name:item.name,directory:item.isDirectory()});
    }
    return entries.sort((a,b)=>Number(b.directory)-Number(a.directory)||a.name.localeCompare(b.name,'ko'));
  }
  async open(relative) {
    if(relative.toLowerCase().endsWith('.pptx')){
      const input=await readFile(await resolveInside(await realpath(this.root),relative)),folder=`.inkdrive/previews/${sha(input)}`;
      const manifest=JSON.parse(await readFile(await resolveInside(this.root,folder+'/manifest.json'),'utf8'));
      const preview=await readFile(await resolveInside(this.root,folder+'/preview.pdf'));
      if(manifest.sourceSHA256!==sha(input)||manifest.previewSHA256!==sha(preview))throw new Error('미리보기 동기화를 기다려 주세요.');
      try{await stat(await resolveInside(this.root,folder+'/notebook.pdf'));relative=folder+'/notebook.pdf';}catch(e){if(e.code!=='ENOENT')throw e;relative=folder+'/preview.pdf';}
    }
    const root=await realpath(this.root),path=await resolveInside(root,relative),info=await stat(path);
    if(!info.isFile()||info.size>256_000_000||!relative.toLowerCase().endsWith('.pdf'))throw new Error('PDF를 선택해 주세요.');
    const key=`${relative}:${info.size}:${info.mtimeMs}`;if(this.current?.key===key&&this.current.ink&&this.current.state==='ready')return this.current;
    const bytes=await readFile(path),fileHash=sha(bytes);
    let ids=[];try{ids=await readdir(await resolveInside(root,'.inkdrive/documents'));}catch(e){if(e.code!=='ENOENT')throw e;}
    for(const id of ids.filter(id=>/^[0-9a-f-]{36}$/.test(id))) {
      let files=[];try{files=await readdir(await resolveInside(root,`.inkdrive/documents/${id}/commits`));}catch{continue;}
      let candidate=null,byPath=false;
      for(const file of files.filter(n=>/^[0-9a-f]{64}\.json$/.test(n))) {
        try {
          const data=await readFile(await resolveInside(root,`.inkdrive/documents/${id}/commits/${file}`));if(sha(data)!==file.slice(0,-5))continue;
          const commit=JSON.parse(data);if(commit.file?.sha256===fileHash)candidate=file.slice(0,-5);
          if(commit.file?.path===relative)byPath=true;
        }catch{}
      }
      if(!candidate&&!byPath)continue;
      let cached=null;const cacheFile=this.cache&&join(this.cache,id+'.json');
      if(cacheFile)try{const v=JSON.parse(await readFile(cacheFile,'utf8'));validateInk(v.ink);const source=Buffer.from(v.source,'base64');if(sha(source)===(v.ink.previewRevision??v.ink.sourceRevision))cached={...v,source};}catch{}
      const latest=await readLatest(root,id,{preferred:candidate??cached?.hash});
      const value=latest.display??cached;
      if(value) {
        if(latest.display?.commit.file?.sha256 && latest.display.commit.file.sha256 !== fileHash) return this.current={key,pdf:bytes,ink:null,state:'waiting',heads:latest.heads.length};
        const background=value.preview??value.source;
        if(cacheFile&&latest.display){await mkdir(this.cache,{recursive:true});const temp=cacheFile+'.'+randomUUID()+'.partial';await writeFile(temp,JSON.stringify({hash:value.hash,ink:value.ink,source:background.toString('base64')}));await rename(temp,cacheFile);}
        return this.current={key,pdf:background,ink:value.ink,state:latest.state,heads:latest.heads.length};
      }
      return this.current={key,pdf:bytes,ink:null,state:latest.state,heads:latest.heads.length};
    }
    return this.current={key,pdf:bytes,ink:null,state:'embedded',heads:0};
  }
}
