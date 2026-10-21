import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,writeFile,mkdir,readFile,rename} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {LibraryReader} from '../windows/reference/library.mjs';
import {makePDF,makeInk} from '../windows/reference/fixture.mjs';
import {saveRevision,canonicalJSON} from '../shared/ink-commits.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
test('Windows opens real PDFs without modifying them and blocks escaping paths',async t=>{
  const root=await mkdtemp(join(tmpdir(),'inkdrive-library-'));t.after(()=>rm(root,{recursive:true,force:true}));
  const pdf=makePDF();await writeFile(join(root,'note.pdf'),pdf);await mkdir(join(root,'.hidden'));
  const reader=new LibraryReader(root);assert.deepEqual((await reader.list()).map(e=>e.name),['note.pdf']);
  assert.equal((await reader.open('note.pdf')).ink,null);assert.deepEqual(await readFile(join(root,'note.pdf')),pdf);
  await assert.rejects(reader.open('../other.pdf'));await assert.rejects(reader.list('../'));
});
test('native-compatible commit connects PDF, independent ink and local cache across a rename',async t=>{
  const root=await mkdtemp(join(tmpdir(),'inkdrive-library-')),cache=await mkdtemp(join(tmpdir(),'inkdrive-cache-'));t.after(()=>Promise.all([rm(root,{recursive:true,force:true}),rm(cache,{recursive:true,force:true})]));
  const source=makePDF(),ink=makeInk(source);await writeFile(join(root,'note.pdf'),source);
  const revision=await saveRevision(root,ink,{source,native:Buffer.from('{}'),deviceId:'ipad'});
  const commit={...revision.commit,file:{path:'note.pdf',sha256:sha(source)}},data=canonicalJSON(commit),hash=sha(data);
  const commits=join(root,'.inkdrive','documents',ink.documentId,'commits');await rm(join(commits,revision.hash+'.json'));await writeFile(join(commits,hash+'.json'),data);
  const reader=new LibraryReader(root,{cache}),opened=await reader.open('note.pdf');assert.equal(opened.ink.documentId,ink.documentId);assert.equal(opened.state,'ready');
  await rename(join(root,'note.pdf'),join(root,'renamed.pdf'));assert.equal((await reader.open('renamed.pdf')).ink.documentId,ink.documentId);
  assert.equal((await readFile(join(cache,ink.documentId+'.json'),'utf8')).includes('sourceRevision'),true);
});
