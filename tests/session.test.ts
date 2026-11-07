import {afterEach,describe,expect,it,vi} from 'vitest';
import {invoke} from '@tauri-apps/api/core';
import {emitTo} from '@tauri-apps/api/event';
import type {LiveConfig,LiveEvent} from '../src/lib/live';
const wire=vi.hoisted(()=>({config:undefined as LiveConfig|undefined,receive:(_event:LiveEvent)=>{},capture:(_event:{payload:Record<string,unknown>})=>{},stop:vi.fn(),audio:vi.fn(),hide:vi.fn(async()=>{})}));
vi.mock('../src/lib/live',()=>({
 LiveClient:class {constructor(receive:(event:LiveEvent)=>void){wire.receive=receive} start(config:LiveConfig){wire.config=config} stop(){wire.stop()} audio(data:string){wire.audio(data)}},
 measurePCM:()=>({db:-96,level:0})
}));
vi.mock('@tauri-apps/api/core',()=>({isTauri:()=>true,invoke:vi.fn(async()=>{})}));
vi.mock('@tauri-apps/api/event',()=>({emitTo:vi.fn(async()=>{}),listen:vi.fn(async(name:string,handler:typeof wire.capture)=>{if(name==='audio')wire.capture=handler;return ()=>{}})}));
vi.mock('@tauri-apps/api/window',()=>({getCurrentWindow:()=>({hide:wire.hide})}));
import {session,settings,init,start,stop,setMode,snapshot,languageStatus,chooseLanguage,languages,showOverlay,preview,setVoice} from '../src/lib/session.svelte';
afterEach(async()=>{await stop();session.overlay=false;session.voice=true;session.mode='conversation';session.first='ko';session.second='en';settings.key='';wire.config=undefined;vi.useRealTimers();vi.clearAllMocks()});
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
  wire.receive({type:'input',text:'안녕하세요',languageCode:'ko-KR',finished:true});expect(session.original).toBe('안녕하세요');
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


it('does not hide the controls behind an idle presentation overlay',async()=>{
 await setMode('overlay');await showOverlay(true);
 expect(wire.hide).not.toHaveBeenCalled();expect(session.overlay).toBe(false);
 expect(session.notice).toContain('통역을 먼저 시작');
});
it('keeps an active presentation running when its main window is hidden',async()=>{
 await setMode('overlay');settings.key='fixture';await start();await wire.receive({type:'ready'});
 const stops=wire.stop.mock.calls.length;await showOverlay(true);
 expect(wire.hide).toHaveBeenCalledOnce();expect(wire.stop).toHaveBeenCalledTimes(stops);
 await wire.receive({type:'input',text:'Hello',finished:true});await wire.receive({type:'output',text:'안녕하세요'});
 expect(snapshot()).toMatchObject({original:'Hello',translation:'안녕하세요',phase:'translating'});
});
it('includes stopped, connecting and failed states in overlay snapshots',async()=>{
 expect(snapshot()).toMatchObject({phase:'idle',status:'통역 준비'});
 await wire.receive({type:'connecting'});expect(snapshot()).toMatchObject({phase:'connecting',status:'Gemini에 연결 중'});
 await wire.receive({type:'error',text:'테스트 연결 오류'});
 expect(snapshot()).toMatchObject({phase:'error',status:'테스트 연결 오류'});
});

it('streams translated captions while presentation audio output is muted',async()=>{
 await setMode('overlay');settings.key='fixture';await start();await wire.receive({type:'ready'});
 expect(session.voice).toBe(false);vi.mocked(invoke).mockClear();
 await wire.receive({type:'output',text:'Hello'});await wire.receive({type:'audio',data:'fixture'});
 expect(snapshot().translation).toBe('Hello');expect(session.phase).toBe('translating');
 await wire.receive({type:'output',text:' world'});expect(snapshot().translation).toBe('Hello world');
 expect(invoke).not.toHaveBeenCalledWith('audio_command',{command:{op:'play',data:'fixture'}});
});
it('permits design previews to hide but blocks paused and failed sessions',async()=>{
 await setMode('overlay');await preview();await showOverlay(true);expect(wire.hide).toHaveBeenCalledOnce();
 await stop('paused');await showOverlay(true);expect(wire.hide).toHaveBeenCalledOnce();
 await stop('error');await showOverlay(true);expect(wire.hide).toHaveBeenCalledOnce();
});
it('does not hide the main window if the session stops while the overlay opens',async()=>{
 await setMode('overlay');settings.key='fixture';await start();await wire.receive({type:'connecting'});
 vi.mocked(invoke).mockImplementationOnce(async()=>{await stop()});await showOverlay(true);
 expect(wire.hide).not.toHaveBeenCalled();expect(session.phase).toBe('idle');
});

describe('continuous capture across silence and transport recovery',()=>{
 it.each(['stop','mode change','new session'])('cancels pending capture setup after %s',async(action)=>{
  settings.key='fixture';await start();vi.mocked(invoke).mockClear();
  let release!:()=>void;vi.mocked(invoke).mockImplementationOnce(()=>new Promise<void>(resolve=>{release=resolve}));
  const pending=wire.receive({type:'ready'});
  if(action==='mode change')await setMode('overlay');
  else await stop();
  if(action==='new session'){await start();await wire.receive({type:'ready'});}
  vi.mocked(invoke).mockClear();release();await pending;
  expect(vi.mocked(invoke).mock.calls.filter(([,args])=>(args as any)?.command?.op==='start')).toHaveLength(0);
  expect(session.phase).toBe(action==='new session'?'listening':'idle');
 });
 it('ignores a late capture-start rejection after user stop',async()=>{
  settings.key='fixture';await start();vi.mocked(invoke).mockClear();
  let rejectStart!:(reason:Error)=>void;
  vi.mocked(invoke).mockImplementationOnce(async()=>{}).mockImplementationOnce(()=>new Promise<void>((_,reject)=>{rejectStart=reject}));
  const pending=wire.receive({type:'ready'});
  await vi.waitFor(()=>expect(invoke).toHaveBeenCalledWith('audio_command',{command:{op:'start',source:settings.source,uid:settings.uid}}));
  await stop();rejectStart(new Error('Late capture failure'));await pending;
  expect(session.phase).toBe('idle');expect(session.error).toBe('');
 });
 it('publishes the native capture error to the overlay and stops forwarding audio',async()=>{
  await init();settings.key='fixture';await start();await wire.receive({type:'ready'});
  vi.mocked(emitTo).mockClear();wire.audio.mockClear();
  wire.capture({payload:{type:'error',message:'시스템 오디오 캡처가 중단됐습니다.'}});
  await vi.waitFor(()=>expect(emitTo).toHaveBeenCalledWith('overlay','caption',expect.objectContaining({phase:'error',status:'시스템 오디오 캡처가 중단됐습니다.'})));
  wire.capture({payload:{type:'pcm',data:'late-error-pcm'}});
  expect(wire.audio).not.toHaveBeenCalled();expect(session.phase).toBe('error');
 });
 it('keeps listening after a completed turn and prolonged silence, then accepts new speech',async()=>{
  await init();settings.key='fixture';await start();await wire.receive({type:'ready'});
  await wire.receive({type:'input',text:'Hello',finished:true});await wire.receive({type:'output',text:'안녕하세요'});
  await wire.receive({type:'complete'});vi.mocked(invoke).mockClear();wire.stop.mockClear();
  vi.useFakeTimers();await vi.advanceTimersByTimeAsync(5*60*1000);
  wire.capture({payload:{type:'pcm',data:'silent-pcm'}});
  expect(session.phase).toBe('listening');expect(session.db).toBe(-96);
  expect(wire.audio).toHaveBeenCalledWith('silent-pcm');expect(wire.stop).not.toHaveBeenCalled();
  expect(invoke).not.toHaveBeenCalledWith('audio_command',{command:{op:'stop'}});
  await wire.receive({type:'input',text:'Next sentence'});await wire.receive({type:'output',text:'다음 문장'});
  expect(session.original).toBe('Next sentence');expect(session.translation).toBe('다음 문장');
 });
 it('preserves capture while reconnecting and clears stale captions and playback',async()=>{
  await init();settings.key='fixture';await start();await wire.receive({type:'ready'});
  await wire.receive({type:'input',text:'Old input',languageCode:'en'});await wire.receive({type:'output',text:'이전 출력'});
  vi.mocked(invoke).mockClear();wire.stop.mockClear();
  await wire.receive({type:'reconnecting'});wire.capture({payload:{type:'pcm',data:'recovery-pcm'}});
  expect(session).toMatchObject({phase:'reconnecting',original:'',translation:'',detected:''});
  expect(wire.audio).toHaveBeenCalledWith('recovery-pcm');
  expect(invoke).toHaveBeenCalledWith('audio_command',{command:{op:'clear'}});
  await wire.receive({type:'ready'});wire.capture({payload:{type:'pcm',data:'resumed-pcm'}});
  expect(session.phase).toBe('listening');expect(wire.audio).toHaveBeenCalledWith('resumed-pcm');
  expect(wire.stop).not.toHaveBeenCalled();
  expect(vi.mocked(invoke).mock.calls.filter(([,args])=>['start','stop'].includes((args as any)?.command?.op))).toHaveLength(0);
  await wire.receive({type:'input',text:'Fresh input'});expect(session.original).toBe('Fresh input');
 });
 it('preserves queued playback and captions on planned rotation, then replaces them on the next turn',async()=>{
  await init();settings.key='fixture';await start();await wire.receive({type:'ready'});
  await wire.receive({type:'input',text:'Previous sentence',languageCode:'en'});
  await wire.receive({type:'output',text:'이전 문장'});await wire.receive({type:'audio',data:'queued-speech'});
  await wire.receive({type:'complete'});vi.mocked(invoke).mockClear();
  await wire.receive({type:'reconnecting',preserveOutput:true});
  expect(session).toMatchObject({phase:'reconnecting',original:'Previous sentence',translation:'이전 문장',detected:'en'});
  wire.capture({payload:{type:'pcm',data:'planned-recovery-pcm'}});
  expect(wire.audio).toHaveBeenCalledWith('planned-recovery-pcm');
  await wire.receive({type:'ready'});
  expect(vi.mocked(invoke).mock.calls.filter(([,args])=>['clear','start','stop'].includes((args as any)?.command?.op))).toHaveLength(0);
  await wire.receive({type:'interim',text:'Fresh'});expect(session.original).toBe('Fresh');expect(session.detected).toBe('');
  await wire.receive({type:'input',text:'Fresh sentence'});await wire.receive({type:'output',text:'새 문장'});
  expect(session.original).toBe('Fresh sentence');expect(session.translation).toBe('새 문장');
 });
 it('stops forwarding captured PCM after an explicit stop',async()=>{
  await init();settings.key='fixture';await start();await wire.receive({type:'ready'});await stop();wire.audio.mockClear();
  wire.capture({payload:{type:'pcm',data:'late-pcm'}});
  expect(wire.audio).not.toHaveBeenCalled();expect(session.phase).toBe('idle');
 });
});


describe('bounded native output failure and interruption',()=>{
 it('keeps capture and captions running after a visible native output failure',async()=>{
  await init();settings.key='fixture';await start();await wire.receive({type:'ready'});
  await wire.receive({type:'input',text:'Original'});await wire.receive({type:'output',text:'번역'});
  const phase=session.phase;wire.stop.mockClear();wire.audio.mockClear();vi.mocked(invoke).mockClear();
  wire.capture({payload:{type:'output-error',message:'출력 한도 초과: 음성 출력을 껐습니다.'}});
  expect(session.voice).toBe(false);expect(session.error).toContain('출력 한도 초과');
  expect(session.phase).toBe(phase);expect(session.original).toBe('Original');expect(session.translation).toBe('번역');
  wire.capture({payload:{type:'pcm',data:'ongoing-input'}});
  expect(wire.audio).toHaveBeenCalledWith('ongoing-input');expect(wire.stop).not.toHaveBeenCalled();
  await wire.receive({type:'audio',data:'no-play-after-failure'});
  expect(invoke).not.toHaveBeenCalledWith('audio_command',{command:{op:'play',data:'no-play-after-failure'}});
  await wire.receive({type:'output',text:' 계속'});await wire.receive({type:'complete'});
  expect(session.translation).toBe('번역 계속');expect(session.error).toContain('출력 한도 초과');
  vi.mocked(invoke).mockClear();await setVoice(true);
  expect(vi.mocked(invoke).mock.calls.slice(0,2)).toEqual([
   ['audio_command',{command:{op:'clear'}}],['audio_command',{command:{op:'volume',value:session.volume}}]
  ]);
 });
 it('marks interruption before awaiting native clear, preserving the new turn',async()=>{
  await wire.receive({type:'output',text:'Old translation'});
  let release!:()=>void;
  vi.mocked(invoke).mockImplementationOnce(()=>new Promise<void>(resolve=>{release=resolve}));
  const interrupted=wire.receive({type:'interrupted'});
  expect(session.phase).toBe('listening');
  await wire.receive({type:'output',text:'New translation'});
  expect(session.translation).toBe('New translation');expect(session.phase).toBe('translating');
  release();await interrupted;
  expect(session.translation).toBe('New translation');expect(session.phase).toBe('translating');
 });
});


describe('independent input transcription boundaries',()=>{
 it('appends late and repeated input deltas after output completion without guessing a new source turn',async()=>{
  settings.key='fixture';await start();await wire.receive({type:'ready'});
  await wire.receive({type:'input',text:'Hello'});await wire.receive({type:'output',text:'안녕하세요'});
  await wire.receive({type:'complete'});
  expect(session.original).toBe('Hello');expect(session.translation).toBe('안녕하세요');
  await wire.receive({type:'input',text:' world'});
  expect(session.original).toBe('Hello world');expect(session.translation).toBe('안녕하세요');
  await wire.receive({type:'output',text:'다음 번역'});await wire.receive({type:'complete'});
  await wire.receive({type:'input',text:' world'});
  expect(session.original).toBe('Hello world world');expect(session.translation).toBe('다음 번역');
 });
 it('keeps a bounded 6000-character rolling input across output turns',async()=>{
  settings.key='fixture';await start();
  await wire.receive({type:'input',text:'a'.repeat(5999)});await wire.receive({type:'complete'});
  await wire.receive({type:'input',text:'BCD'});
  expect(session.original).toBe('a'.repeat(5997)+'BCD');
 });
 it('does not erase a connection error when voice is re-enabled',async()=>{
  await wire.receive({type:'error',text:'Connection failed'});
  await setVoice(true);
  expect(session.error).toBe('Connection failed');expect(session.phase).toBe('error');
 });
});
