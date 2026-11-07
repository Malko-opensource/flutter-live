import {describe,it,expect,vi,afterEach} from 'vitest';
import {LiveClient,setup,measurePCM,type SocketLike,type LiveEvent} from '../src/lib/live';
class Socket implements SocketLike {readyState=1;bufferedAmount=0;onopen:SocketLike['onopen']=null;onmessage:SocketLike['onmessage']=null;onerror:SocketLike['onerror']=null;onclose:SocketLike['onclose']=null;sent:string[]=[];send(data:string){this.sent.push(data)}close(){this.readyState=3}message(value:unknown){this.onmessage?.({data:JSON.stringify(value)} as MessageEvent)}}
const config={mode:'conversation' as const,key:'test-secret',first:'Korean',second:'English',firstCode:'ko',secondCode:'en'};
afterEach(()=>vi.useRealTimers());
describe('Live stream lifecycle',()=>{
 it('gates audio on setup and bounds reconnect memory',()=>{vi.useFakeTimers();const s=new Socket();const client=new LiveClient(()=>{},()=>s);client.start(config);s.onopen?.(new Event('open'));for(let i=0;i<150;i++)client.audio('pcm');expect(client.bufferedChunks).toBe(100);vi.advanceTimersByTime(20);expect(s.sent.length).toBe(1);s.message({setupComplete:{}});vi.advanceTimersByTime(20);expect(s.sent.length).toBe(5);expect(client.bufferedChunks).toBe(96);client.stop();});
 it('drops audio in interrupted packets and returns both transcripts',()=>{vi.useFakeTimers();const s=new Socket();const events:LiveEvent[]=[];const c=new LiveClient(e=>events.push(e),()=>s);c.start(config);s.message({serverContent:{interrupted:true,inputTranscription:{text:'안녕',finished:true},outputTranscription:{text:'Hello'},modelTurn:{parts:[{inlineData:{mimeType:'audio/pcm',data:'old'}}]}}});expect(events.map(e=>e.type)).toEqual(['connecting','interrupted','input','output']);c.stop();});
 it('uses a resume handle and cancels retry on stop',()=>{vi.useFakeTimers();const sockets:Socket[]=[];const c=new LiveClient(()=>{},()=>{const s=new Socket();sockets.push(s);return s});c.start(config);sockets[0].message({sessionResumptionUpdate:{resumable:true,newHandle:'resume'},goAway:{}});vi.advanceTimersByTime(1400);expect(sockets).toHaveLength(2);sockets[1].onopen?.(new Event('open'));expect(JSON.parse(sockets[1].sent[0]).setup.sessionResumption.handle).toBe('resume');sockets[1].onerror?.(new Event('error'));c.stop();vi.advanceTimersByTime(60000);expect(sockets).toHaveLength(2);});
 it('never exposes provider error details or keys',()=>{vi.useFakeTimers();const s=new Socket();const events:LiveEvent[]=[];const c=new LiveClient(e=>events.push(e),()=>s);c.start(config);s.message({error:{code:403,message:'test-secret'}});expect(events.at(-1)?.type).toBe('error');expect(JSON.stringify(events)).not.toContain('test-secret');c.stop();});
 it('ignores stale responses after stop',()=>{vi.useFakeTimers();const s=new Socket();const events:LiveEvent[]=[];const c=new LiveClient(e=>events.push(e),()=>s);c.start(config);c.stop();s.message({setupComplete:{},serverContent:{outputTranscription:{text:'late'}}});expect(events).toHaveLength(1)});
});
it('sets two-way interpreter constraints and audio transcripts',()=>{const s=setup(config).setup;expect(s.model).toBe('models/gemini-3.8-live');expect(s.systemInstruction.parts[0].text).toContain('Korean and English');expect(s).toHaveProperty('inputAudioTranscription');expect(s).toHaveProperty('outputAudioTranscription')});
it('measures PCM16 silence and amplitude',()=>{expect(measurePCM(btoa('\0'.repeat(640))).db).toBe(-96);const raw=String.fromCharCode(0,32).repeat(320);expect(measurePCM(btoa(raw)).db).toBeCloseTo(-12.04,1)});

it('bounds input even while the socket send buffer is congested',()=>{vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);s.message({setupComplete:{}});s.bufferedAmount=65536;for(let i=0;i<200;i++)c.audio('pcm');vi.advanceTimersByTime(100);expect(s.sent).toHaveLength(0);expect(c.bufferedChunks).toBe(100);s.bufferedAmount=0;vi.advanceTimersByTime(20);expect(s.sent).toHaveLength(4);c.stop()});
it('rejects unsupported output rates instead of playing them at the wrong pitch',()=>{vi.useFakeTimers();const s=new Socket();const events:LiveEvent[]=[];const c=new LiveClient(e=>events.push(e),()=>s);c.start(config);s.message({serverContent:{modelTurn:{parts:[{inlineData:{mimeType:'audio/pcm;rate=48000',data:'pcm'}}]}}});expect(events.at(-1)?.type).toBe('error');expect(events.some(e=>e.type==='audio')).toBe(false);c.stop()});

it('sends a fixed source hint and target instruction for presentations',()=>{
 const s=setup({...config,mode:'presentation',first:'English',second:'Korean',firstCode:'en',secondCode:'ko'}).setup;
 expect(s.inputAudioTranscription.languageCodes).toEqual(['en']);
 expect(s.systemInstruction.parts[0].text).toContain('Always output in Korean');
 expect(s.systemInstruction.parts[0].text).toContain('Never reverse');
 expect(s.systemInstruction.parts[0].text).not.toContain('bidirectional');
 expect(s.generationConfig.speechConfig).not.toHaveProperty('languageCode');
 expect(s.outputAudioTranscription).toEqual({});
});
it('keeps both language hints and per-utterance switching for conversation',()=>{
 const s=setup(config).setup;
 expect(s.inputAudioTranscription.languageCodes).toEqual(['ko','en']);
 expect(s.systemInstruction.parts[0].text).toContain('If the user speaks Korean, output the translation ONLY in English');
 expect(s.systemInstruction.parts[0].text).toContain('If the user speaks English, output the translation ONLY in Korean');
});
it('passes server language metadata and interim rewrites without guessing from text',()=>{
 vi.useFakeTimers();const s=new Socket();const events:LiveEvent[]=[];const c=new LiveClient(e=>events.push(e),()=>s);c.start(config);
 s.message({serverContent:{interimInputTranscription:{text:'안',languageCode:'ko-KR'}}});
 s.message({serverContent:{inputTranscription:{text:'안녕',languageCode:'ko-KR'},interimInputTranscription:{text:'stale'}}});
 s.message({serverContent:{inputTranscription:{text:'Hello',languageCode:'en-US'}}});
 expect(events.filter(e=>e.type==='input'||e.type==='interim').map(e=>[e.type,e.text,e.languageCode])).toEqual([['interim','안','ko-KR'],['input','안녕','ko-KR'],['input','Hello','en-US']]);c.stop();
});

it('pins the model for each mode even when stale callers include a model override',()=>{
 for(const mode of ['conversation','presentation'] as const){
  const stale={...config,mode,model:'unexpected-model'};
  expect(setup(stale).setup.model).toBe('models/gemini-3.8-live');
  expect(setup(stale,'resume').setup.model).toBe('models/gemini-3.8-live');
 }
});


it('does not interrupt presentation translation when the speaker resumes',()=>{
 expect(setup({...config,mode:'presentation'}).setup.realtimeInputConfig.activityHandling).toBe('NO_INTERRUPTION');
 expect(setup(config).setup.realtimeInputConfig.activityHandling).toBe('START_OF_ACTIVITY_INTERRUPTS');
});
it('forwards live microphone chunks without waiting for background webview timers',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start({...config,mode:'presentation'});
 s.message({setupComplete:{}});c.audio('first');c.audio('second');
 expect(s.sent.map(raw=>JSON.parse(raw).realtimeInput.audio.data)).toEqual(['first','second']);
 expect(c.bufferedChunks).toBe(0);c.stop();
});
it('drains queued audio in order on capture events when background timers are delayed',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);
 for(let i=0;i<6;i++)c.audio(String(i));s.message({setupComplete:{}});c.audio('new');
 expect(s.sent.map(raw=>JSON.parse(raw).realtimeInput.audio.data)).toEqual(['0','1','2','3']);
 expect(c.bufferedChunks).toBe(3);c.stop();
});

it('resumes capture-driven sends after backpressure clears without a timer tick',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);s.message({setupComplete:{}});
 s.bufferedAmount=65536;c.audio('queued');expect(s.sent).toHaveLength(0);
 s.bufferedAmount=0;c.audio('next');expect(s.sent.map(raw=>JSON.parse(raw).realtimeInput.audio.data)).toEqual(['queued','next']);c.stop();
});
it('stops a capture-driven flush immediately when send fails',()=>{
 vi.useFakeTimers();const s=new Socket();const events:LiveEvent[]=[];const c=new LiveClient(e=>events.push(e),()=>s);c.start(config);
 c.audio('queued');s.message({setupComplete:{}});const send=vi.spyOn(s,'send').mockImplementation(()=>{throw new Error('offline')});
 c.audio('next');expect(send).toHaveBeenCalledOnce();expect(events.at(-1)?.type).toBe('reconnecting');
 c.audio('later');expect(send).toHaveBeenCalledOnce();c.stop();
});
it('does not drain audio into a closed socket',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);s.message({setupComplete:{}});s.close();c.audio('queued');
 expect(s.sent).toHaveLength(0);expect(c.bufferedChunks).toBe(1);c.stop();
});

describe('persistent live recovery',()=>{
 function harness(){vi.useFakeTimers();const sockets:Socket[]=[];const events:LiveEvent[]=[];const c=new LiveClient(e=>events.push(e),()=>{const s=new Socket();sockets.push(s);return s});c.start(config);return {c,sockets,events};}
 it('waits through prolonged silence without fake keepalives and accepts later speech',()=>{
  const {c,sockets,events}=harness();const s=sockets[0];s.message({setupComplete:{}});
  vi.advanceTimersByTime(20*60*1000);expect(sockets).toHaveLength(1);expect(s.sent).toHaveLength(0);expect(events.some(e=>e.type==='error')).toBe(false);
  c.audio('speech-after-silence');expect(JSON.parse(s.sent[0]).realtimeInput.audio.data).toBe('speech-after-silence');c.stop();
 });
 it('keeps retrying beyond six transport failures with bounded delay and memory',()=>{
  const {c,sockets,events}=harness();
  for(let i=0;i<12;i++){const s=sockets.at(-1)!;s.message({setupComplete:{}});s.onerror?.(new Event('error'));for(let j=0;j<150;j++)c.audio('pcm');expect(c.bufferedChunks).toBe(100);vi.advanceTimersByTime(10301);expect(sockets.length).toBe(i+2);}
  expect(events.some(e=>e.type==='error')).toBe(false);const s=sockets.at(-1)!;s.message({setupComplete:{}});c.audio('fresh');expect(JSON.parse(s.sent.at(-1)!).realtimeInput.audio.data).toBe('fresh');c.stop();
 });
 it('recovers setup timeouts and ignores stale callbacks including asynchronous Blob reads',async()=>{
  const {c,sockets,events}=harness();const old=sockets[0];let resolve!:(s:string)=>void;
  const blob=new Blob();vi.spyOn(blob,'text').mockImplementation(()=>new Promise(r=>resolve=r));old.onmessage?.({data:blob} as MessageEvent);
  vi.advanceTimersByTime(13400);expect(sockets).toHaveLength(2);const before=events.length;
  old.onopen?.(new Event('open'));old.onclose?.({code:1008} as CloseEvent);old.onerror?.(new Event('error'));old.message({setupComplete:{}});resolve(JSON.stringify({serverContent:{outputTranscription:{text:'stale'}}}));await Promise.resolve();await Promise.resolve();
  expect(events).toHaveLength(before);expect(old.sent).toHaveLength(0);c.stop();expect(vi.getTimerCount()).toBe(0);
 });
 it('does not lose an unsent chunk on send exception, and retries in order',()=>{
  const {c,sockets}=harness();const s=sockets[0];s.message({setupComplete:{}});vi.spyOn(s,'send').mockImplementation(()=>{throw new Error('offline')});
  c.audio('first');c.audio('second');expect(c.bufferedChunks).toBe(2);vi.advanceTimersByTime(1400);const next=sockets[1];next.message({setupComplete:{}});vi.advanceTimersByTime(20);
  expect(next.sent.map(raw=>JSON.parse(raw).realtimeInput.audio.data)).toEqual(['first','second']);expect(c.bufferedChunks).toBe(0);c.stop();
 });
 it('expires queued audio by age even without new capture',()=>{
  const {c}=harness();c.audio('old');vi.advanceTimersByTime(2020);expect(c.bufferedChunks).toBe(0);c.stop();
 });
 it('finishes the active turn before immediate planned rotation',()=>{
  const {c,sockets,events}=harness();const s=sockets[0];s.message({setupComplete:{}});s.message({serverContent:{outputTranscription:{text:'part one'}}});
  s.message({goAway:{timeLeft:'10s'}});vi.advanceTimersByTime(2000);expect(s.readyState).toBe(1);expect(sockets).toHaveLength(1);
  s.message({serverContent:{outputTranscription:{text:'part two'},turnComplete:true},sessionResumptionUpdate:{resumable:true,newHandle:'latest'}});vi.advanceTimersByTime(0);expect(sockets).toHaveLength(2);sockets[1].onopen?.(new Event('open'));expect(JSON.parse(sockets[1].sent[0]).setup.sessionResumption).toEqual({handle:'latest'});expect(events.filter(e=>e.type==='output').map(e=>e.text)).toEqual(['part one','part two']);c.stop();
 });
 it('rotates before the goAway deadline if the turn cannot finish',()=>{
  const {c,sockets}=harness();const s=sockets[0];s.message({setupComplete:{},serverContent:{inputTranscription:{text:'speaking'}}});s.message({goAway:{timeLeft:'2.5s'}});
  vi.advanceTimersByTime(1999);expect(sockets).toHaveLength(1);vi.advanceTimersByTime(2);expect(sockets).toHaveLength(2);c.stop();
 });
 it('clears non-resumable handles and starts a fresh session',()=>{
  const {c,sockets}=harness();const s=sockets[0];s.message({setupComplete:{},sessionResumptionUpdate:{resumable:true,newHandle:'stale'}});s.message({sessionResumptionUpdate:{resumable:false},goAway:{}});vi.advanceTimersByTime(0);sockets[1].onopen?.(new Event('open'));expect(JSON.parse(sockets[1].sent[0]).setup.sessionResumption).toEqual({});c.stop();
 });
 it.each(['error','close','timeout'])('falls back from a rejected or timed out resumed setup (%s)',kind=>{
  const {c,sockets,events}=harness();sockets[0].message({setupComplete:{},sessionResumptionUpdate:{resumable:true,newHandle:'stale'},goAway:{}});vi.advanceTimersByTime(0);const resumed=sockets[1];resumed.onopen?.(new Event('open'));expect(JSON.parse(resumed.sent[0]).setup.sessionResumption.handle).toBe('stale');
  if(kind==='error')resumed.message({error:{code:400,message:'invalid handle'}});else if(kind==='close')resumed.onclose?.({code:1008} as CloseEvent);else vi.advanceTimersByTime(12000);
  vi.advanceTimersByTime(2400);const fresh=sockets[2];fresh.onopen?.(new Event('open'));expect(JSON.parse(fresh.sent[0]).setup.sessionResumption).toEqual({});expect(events.some(e=>e.type==='error')).toBe(false);c.stop();
 });
 it('still stops on permanent authentication errors instead of retrying indefinitely',()=>{
  const {c,sockets,events}=harness();sockets[0].message({error:{code:403}});vi.advanceTimersByTime(60000);expect(sockets).toHaveLength(1);expect(events.at(-1)?.type).toBe('error');expect(vi.getTimerCount()).toBe(0);c.stop();
 });
 it('cancels planned rotation and all timers on stop',()=>{
  const {c,sockets}=harness();sockets[0].message({setupComplete:{},serverContent:{outputTranscription:{text:'active'}},goAway:{timeLeft:'20s'}});c.stop();vi.advanceTimersByTime(60000);expect(sockets).toHaveLength(1);expect(vi.getTimerCount()).toBe(0);
 });
 it('detects an already closed transport without mistaking silence for a failure',()=>{
  const {c,sockets,events}=harness();sockets[0].message({setupComplete:{}});sockets[0].close();vi.advanceTimersByTime(20);expect(events.at(-1)?.type).toBe('reconnecting');c.stop();
 });
});

it('flushes a paused capture stream once, keeps the session open, and resumes next PCM',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);s.message({setupComplete:{}});c.audio('speech');
 vi.advanceTimersByTime(999);expect(s.sent).toHaveLength(1);vi.advanceTimersByTime(1);expect(JSON.parse(s.sent[1])).toEqual({realtimeInput:{audioStreamEnd:true}});
 vi.advanceTimersByTime(60000);expect(s.sent).toHaveLength(2);expect(s.readyState).toBe(1);c.audio('resumed');expect(JSON.parse(s.sent[2]).realtimeInput.audio.data).toBe('resumed');
 vi.advanceTimersByTime(1000);expect(s.sent.filter(raw=>JSON.parse(raw).realtimeInput.audioStreamEnd)).toHaveLength(2);c.stop();
});
it('does not end continuous silent PCM or send capture-gap signals before setup',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);c.audio('silence');vi.advanceTimersByTime(1500);expect(s.sent).toHaveLength(0);
 s.message({setupComplete:{}});for(let i=0;i<200;i++){c.audio(btoa('\0'.repeat(640)));vi.advanceTimersByTime(20);}
 expect(s.sent.every(raw=>!JSON.parse(raw).realtimeInput.audioStreamEnd)).toBe(true);c.stop();
});

it('recovers an OPEN transport only after five seconds of queued input with no send progress',()=>{
 vi.useFakeTimers();const sockets:Socket[]=[];const c=new LiveClient(()=>{},()=>{const s=new Socket();sockets.push(s);return s});c.start(config);const s=sockets[0];s.message({setupComplete:{}});s.bufferedAmount=65536;
 for(let i=0;i<250;i++){c.audio('pcm');vi.advanceTimersByTime(20);}expect(s.readyState).toBe(3);expect(sockets).toHaveLength(1);
 vi.advanceTimersByTime(500);expect(sockets).toHaveLength(2);c.stop();
});
it('does not treat an idle or progressing send buffer as a stalled transport',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);s.message({setupComplete:{}});s.bufferedAmount=100000;
 vi.advanceTimersByTime(10000);expect(s.readyState).toBe(1);
 for(let i=0;i<400;i++){if(i%100===0)s.bufferedAmount-=1000;c.audio('pcm');vi.advanceTimersByTime(20);}expect(s.readyState).toBe(1);
 s.bufferedAmount=0;c.audio('recovered');vi.advanceTimersByTime(500);expect(s.readyState).toBe(1);c.stop();
});
it('resets the congestion watchdog when queued audio expires or pressure clears',()=>{
 vi.useFakeTimers();const s=new Socket();const c=new LiveClient(()=>{},()=>s);c.start(config);s.message({setupComplete:{}});s.bufferedAmount=65536;c.audio('old');
 vi.advanceTimersByTime(6000);expect(s.readyState).toBe(1);
 for(let i=0;i<200;i++){c.audio('pcm');vi.advanceTimersByTime(20);}expect(s.readyState).toBe(1);
 s.bufferedAmount=0;c.audio('clear');s.bufferedAmount=65536;for(let i=0;i<200;i++){c.audio('pcm');vi.advanceTimersByTime(20);}expect(s.readyState).toBe(1);c.stop();expect(vi.getTimerCount()).toBe(0);
});
it('retries transient transport loss within 250–500ms',()=>{
 vi.useFakeTimers();const sockets:Socket[]=[];const c=new LiveClient(()=>{},()=>{const s=new Socket();sockets.push(s);return s});c.start(config);sockets[0].message({setupComplete:{}});sockets[0].onerror?.(new Event('error'));
 vi.advanceTimersByTime(249);expect(sockets).toHaveLength(1);vi.advanceTimersByTime(251);expect(sockets).toHaveLength(2);c.stop();
});
it('backs repeated rate limits off to thirty seconds rather than rapid retries',()=>{
 vi.useFakeTimers();const sockets:Socket[]=[];const c=new LiveClient(()=>{},()=>{const s=new Socket();sockets.push(s);return s});c.start(config);
 for(let i=0;i<7;i++){sockets.at(-1)!.message({error:{code:429}});const minimum=Math.min(1000*2**i,30000);vi.advanceTimersByTime(minimum-1);expect(sockets).toHaveLength(i+1);vi.advanceTimersByTime(251);expect(sockets).toHaveLength(i+2);}
 c.stop();
});

it('preserves output through both planned reconnect notifications but not a failed resume',()=>{
 vi.useFakeTimers();const events:LiveEvent[]=[];const sockets:Socket[]=[];const c=new LiveClient(e=>events.push(e),()=>{const s=new Socket();sockets.push(s);return s});c.start(config);
 sockets[0].message({setupComplete:{},sessionResumptionUpdate:{resumable:true,newHandle:'resume'},serverContent:{outputTranscription:{text:'tail'}}});sockets[0].message({goAway:{timeLeft:'5s'}});sockets[0].message({serverContent:{turnComplete:true}});vi.advanceTimersByTime(0);
 expect(events.filter(e=>e.type==='reconnecting').map(e=>e.preserveOutput)).toEqual([true,true]);
 sockets[1].message({error:{code:400}});vi.advanceTimersByTime(0);expect(events.filter(e=>e.type==='reconnecting').slice(-2).every(e=>!e.preserveOutput)).toBe(true);c.stop();
});
