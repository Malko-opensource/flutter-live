import {readFileSync} from 'node:fs';
import {it,expect} from 'vitest';
it('keeps the hidden main webview running while presentation captions are visible',()=>{
 const config=JSON.parse(readFileSync(new URL('../src-tauri/tauri.conf.json',import.meta.url),'utf8'));
 expect(config.app.windows.find((window:{label:string})=>window.label==='main').backgroundThrottling).toBe('disabled');
});
