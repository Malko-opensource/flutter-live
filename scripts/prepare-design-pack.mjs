import {mkdtempSync,mkdirSync,rmSync,renameSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const directory=mkdtempSync(join(tmpdir(),'flutter-live-design-'));
const checkout=join(directory,'atlas-design-pack');
const commit='765b3c44515a59578347c595bfefaff24b19f694';
function run(command,args,cwd=root){execFileSync(command,args,{cwd,stdio:'inherit'});}
try {
  mkdirSync(resolve(root,'vendor'),{recursive:true});
  run('git',['clone','--no-checkout','ssh://git@gitlab.hansol.net:2222/hansol-pns/ai/atlas-code/atlas-design-pack.git',checkout]);
  run('git',['checkout','--detach',commit],checkout);
  run('npm',['ci'],checkout);
  run('npm',['run','build'],checkout);
  run('npm',['pack','--workspace','@imfacto/svelte','--pack-destination',resolve(root,'vendor')],checkout);
  renameSync(resolve(root,'vendor/imfacto-svelte-0.1.0.tgz'),resolve(root,'vendor/imfacto-svelte-0.1.0-765b3c4.tgz'));
  console.log('Design package prepared. Run npm ci next.');
} finally {rmSync(directory,{recursive:true,force:true});}
