import {mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const directory=mkdtempSync(join(tmpdir(),'flutter-live-design-'));
const checkout=join(directory,'atlas-design-pack');
const commit='2466107017cc628d0c3d370c6db6764b9453ddeb';
function run(command,args,cwd=root){execFileSync(command,args,{cwd,stdio:'inherit'});}
try {
  mkdirSync(resolve(root,'vendor'),{recursive:true});
  run('git',['clone','--no-checkout','ssh://git@gitlab.hansol.net:2222/hansol-pns/ai/atlas-code/atlas-design-pack.git',checkout]);
  run('git',['checkout','--detach',commit],checkout);
  run('npm',['ci'],checkout);
  run('npm',['run','build'],checkout);
  run('npm',['pack','--workspace','@imfacto/svelte','--pack-destination',resolve(root,'vendor')],checkout);
  console.log('Design package prepared. Run npm ci next.');
} finally {rmSync(directory,{recursive:true,force:true});}
