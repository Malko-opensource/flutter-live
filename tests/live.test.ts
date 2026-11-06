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
