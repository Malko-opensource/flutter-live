import {afterEach,describe,expect,it,vi} from 'vitest';
import type {LiveConfig,LiveEvent} from '../src/lib/live';
const wire=vi.hoisted(()=>({config:undefined as LiveConfig|undefined,receive:(_event:LiveEvent)=>{},stop:vi.fn(),audio:vi.fn()}));
vi.mock('../src/lib/live',()=>({
 LiveClient:class {constructor(receive:(event:LiveEvent)=>void){wire.receive=receive} start(config:LiveConfig){wire.config=config} stop(){wire.stop()} audio(){}},
 measurePCM:()=>({db:-96,level:0})
}));
vi.mock('@tauri-apps/api/core',()=>({isTauri:()=>true,invoke:vi.fn(async()=>{})}));
vi.mock('@tauri-apps/api/event',()=>({emitTo:vi.fn(async()=>{}),listen:vi.fn(async()=>()=>{})}));
import {session,settings,start,stop,setMode,snapshot,languageStatus,chooseLanguage,languages} from '../src/lib/session.svelte';
afterEach(async()=>{await stop();session.mode='conversation';session.first='ko';session.second='en';settings.key='';wire.config=undefined;vi.clearAllMocks()});
describe('mode-specific session contract',()=>{
 it('starts the presentation with the selected source and target',async()=>{
  await setMode('overlay');session.first='en';session.second='ko';settings.key='fixture';await start();
  expect(wire.config).toMatchObject({mode:'presentation',first:'English',second:'Korean',firstCode:'en',secondCode:'ko'});
  expect(snapshot().label).toContain('English → 한국어');expect(languageStatus()).toBe('번역 방향 고정');
 });
 it('stops an active session before changing modes, requiring an explicit new start',async()=>{
  settings.key='fixture';await start();wire.receive({type:'connecting'});const calls=wire.stop.mock.calls.length;
  await setMode('overlay');
  expect(wire.stop.mock.calls.length).toBeGreaterThan(calls);expect(session.phase).toBe('idle');expect(session.notice).toContain('다시 시작');
  expect(wire.config).not.toHaveProperty('model');expect(settings).not.toHaveProperty('model');
  expect(wire.config?.mode).toBe('conversation'); // No silent restart or extra provider call.
  await start();expect(wire.config?.mode).toBe('presentation');
 });
 it('shows only metadata-backed detection in conversation and replaces interim captions',async()=>{
  wire.receive({type:'interim',text:'안',languageCode:'ko-KR'});wire.receive({type:'interim',text:'안녕하세요',languageCode:'ko-KR'});
  expect(session.original).toBe('안녕하세요');expect(languageStatus()).toBe('한국어 감지');
  wire.receive({type:'input',text:'안녕하세요',languageCode:'ko-KR'});expect(session.original).toBe('안녕하세요');
  wire.receive({type:'complete'});wire.receive({type:'input',text:'Hello',languageCode:'en-US'});
  expect(session.original).toBe('Hello');expect(languageStatus()).toBe('English 감지');
 });
});

it('keeps all four languages visible and swaps an already-selected target',async()=>{
 expect(languages.map(l=>l.code)).toEqual(['ko','en','ja','zh']);
 await setMode('overlay');chooseLanguage('first','en');
 expect([session.first,session.second]).toEqual(['en','ko']);
 settings.key='fixture';await start();expect(wire.config).toMatchObject({firstCode:'en',secondCode:'ko'});
 wire.receive({type:'connecting'});chooseLanguage('first','zh');expect(session.first).toBe('en');
});
