import {interpreterInstruction,modeModels,type LanguagePair} from './interpreter';
export type LiveConfig=LanguagePair & {key:string};
export type LiveEvent={type:'ready'|'connecting'|'reconnecting'|'input'|'interim'|'output'|'audio'|'interrupted'|'complete'|'error';text?:string;data?:string;finished?:boolean;languageCode?:string;preserveOutput?:boolean};
export interface SocketLike {readyState:number;readonly bufferedAmount?:number;onopen:((e:Event)=>void)|null;onmessage:((e:MessageEvent)=>void)|null;onerror:((e:Event)=>void)|null;onclose:((e:CloseEvent)=>void)|null;send:(data:string)=>void;close:()=>void}
// A presentation keeps speaking while its translation is being generated.
// Only conversation mode should treat new speech as a request to interrupt.
export function setup(config:LiveConfig,handle?:string){return {setup:{model:`models/${modeModels[config.mode]}`,generationConfig:{responseModalities:['AUDIO'],speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:'Kore'}}}},systemInstruction:{parts:[{text:interpreterInstruction(config)}]},inputAudioTranscription:{languageCodes:config.mode==='presentation'?[config.firstCode]:[config.firstCode,config.secondCode]},outputAudioTranscription:{},realtimeInputConfig:{automaticActivityDetection:{silenceDurationMs:350,prefixPaddingMs:100},activityHandling:config.mode==='presentation'?'NO_INTERRUPTION':'START_OF_ACTIVITY_INTERRUPTS'},sessionResumption:handle?{handle}:{},contextWindowCompression:{slidingWindow:{}}}}}
export class LiveClient {
 private socket?:SocketLike;private config?:LiveConfig;private epoch=0;private running=false;private ready=false;private attempt=0;private handle?:string;private resuming=false;private turnActive=false;private rotating=false;private audioStreamOpen=false;private lastAudioAt=0;private blockedSince?:number;private lastBuffered=0;
 private queue:{data:string;at:number}[]=[];private rotation?:ReturnType<typeof setTimeout>;private retry?:ReturnType<typeof setTimeout>;private deadline?:ReturnType<typeof setTimeout>;private stable?:ReturnType<typeof setTimeout>;private pump?:ReturnType<typeof setInterval>;
 constructor(private event:(event:LiveEvent)=>void,private factory:(url:string)=>SocketLike=url=>new WebSocket(url)){}
 start(config:LiveConfig){this.stop();this.running=true;this.config=config;this.pump=setInterval(()=>this.flushAudio(),20);this.connect();}
 audio(data:string){if(this.running){this.queue.push({data,at:Date.now()});if(this.queue.length>100)this.queue.shift();this.flushAudio();}}
 // Capture events keep the stream moving when a hidden webview delays timers.
 // The timer remains a bounded retry for queued audio after socket congestion.
 private flushAudio(){
  // Keep at most two seconds of capture; never replay old speech after an outage.
  while(this.queue.length&&Date.now()-this.queue[0].at>2000)this.queue.shift();
  if(this.ready&&this.socket&&this.socket.readyState>1){this.recover(this.epoch);return;}
  const buffered=this.socket?.bufferedAmount??0;
  // Only queued input plus a send buffer that makes no progress is a stall.
  // Lack of server output (including arbitrarily long silence) is not one.
  if(this.ready&&this.socket?.readyState===1&&this.queue.length&&buffered>=65536){
   if(this.blockedSince===undefined||buffered<this.lastBuffered)this.blockedSince=Date.now();
   this.lastBuffered=buffered;
   if(Date.now()-this.blockedSince>=5000){this.recover(this.epoch);return;}
  }else{this.blockedSince=undefined;this.lastBuffered=0;}
  for(let i=0;i<4&&this.ready&&this.socket?.readyState===1&&this.queue.length&&(this.socket.bufferedAmount??0)<65536;i++){
   if(!this.send({realtimeInput:{audio:{data:this.queue[0].data,mimeType:'audio/pcm;rate=16000'}}}))break;
   this.queue.shift();this.audioStreamOpen=true;this.lastAudioAt=Date.now();
  }
  // A capture gap is not silence: flush VAD once, but keep listening on this
  // session. Continuous PCM silence never needs an artificial keepalive.
  if(this.ready&&this.audioStreamOpen&&!this.queue.length&&Date.now()-this.lastAudioAt>=1000&&(this.socket?.bufferedAmount??0)<65536){
   if(this.send({realtimeInput:{audioStreamEnd:true}}))this.audioStreamOpen=false;
  }
 }
 get bufferedChunks(){return this.queue.length;}
 private connect(preserveOutput=false){
  if(!this.running||!this.config)return;const epoch=++this.epoch;this.ready=false;this.blockedSince=undefined;this.lastBuffered=0;this.audioStreamOpen=false;this.turnActive=false;this.rotating=false;this.resuming=!!this.handle;
  this.event({type:this.attempt?'reconnecting':'connecting',...(preserveOutput?{preserveOutput:true}:{})});
  try {const socket=this.factory(`wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${encodeURIComponent(this.config.key)}`);this.socket=socket;
   this.deadline=setTimeout(()=>this.recover(epoch),12000);
   socket.onopen=()=>{if(epoch===this.epoch)this.send(setup(this.config!,this.handle));};
   socket.onmessage=async e=>{try{const raw=e.data instanceof Blob?await e.data.text():e.data;if(epoch===this.epoch)this.receive(JSON.parse(raw),epoch);}catch{if(epoch===this.epoch)this.fail('서버 응답을 읽지 못했습니다. 다시 시작해 주세요.');}};
   socket.onerror=()=>this.recover(epoch);
   socket.onclose=e=>{if(epoch!==this.epoch)return;if(!this.ready&&this.resuming){this.handle=undefined;this.recover(epoch,true);}else if([1003,1007,1008].includes(e.code))this.fail('연결이 거부됐습니다. API 키와 해당 키의 사용 권한을 확인해 주세요.');else this.recover(epoch);};
  }catch{this.recover(epoch);}
 }
 private receive(m:any,epoch:number){
  if(m.error){if(!this.ready&&this.resuming&&[400,404].includes(m.error.code)){this.handle=undefined;this.recover(epoch,true);}else if([429,500,502,503,504].includes(m.error.code))this.recover(epoch,false,m.error.code===429);else this.fail('Gemini 요청이 거부됐습니다. API 키·사용 권한·사용 한도를 확인해 주세요.');return;}
  if(m.setupComplete!==undefined&&!this.ready){clearTimeout(this.deadline);this.ready=true;this.stable=setTimeout(()=>{if(epoch===this.epoch)this.attempt=0;},30000);this.event({type:'ready'});}
  if(m.sessionResumptionUpdate){const update=m.sessionResumptionUpdate;if(update.resumable&&update.newHandle)this.handle=update.newHandle;else if(update.resumable===false)this.handle=undefined;}
  const c=m.serverContent;
  if(c){
   if(c.inputTranscription||c.interimInputTranscription||c.modelTurn||c.outputTranscription)this.turnActive=true;
   if(c.interrupted)this.event({type:'interrupted'});
   if(c.inputTranscription)this.event({type:'input',text:c.inputTranscription.text??'',finished:!!c.inputTranscription.finished,languageCode:c.inputTranscription.languageCode});
   else if(c.interimInputTranscription)this.event({type:'interim',text:c.interimInputTranscription.text??'',languageCode:c.interimInputTranscription.languageCode});
   if(c.outputTranscription)this.event({type:'output',text:c.outputTranscription.text??'',languageCode:c.outputTranscription.languageCode});
   if(!c.interrupted)for(const p of c.modelTurn?.parts??[]){if(p.inlineData?.mimeType?.startsWith('audio/pcm')){const rate=/rate=(\d+)/.exec(p.inlineData.mimeType)?.[1];if(rate&&rate!=='24000'){this.fail('지원하지 않는 음성 출력 형식입니다. 앱 업데이트를 확인해 주세요.');return;}this.event({type:'audio',data:p.inlineData.data});}}
   if(c.turnComplete){this.turnActive=false;this.event({type:'complete'});if(this.rotating){this.recover(epoch,true,false,true);return;}}
  }
  if(m.goAway&&!this.rotating){
   // GoAway is advance notice, not a disconnect. Finish current translation
   // while time remains, then reconnect immediately rather than using backoff.
   if(!this.turnActive){this.recover(epoch,true,false,true);return;}
   this.rotating=true;
   const seconds=typeof m.goAway.timeLeft==='string'&&/^\d+(\.\d+)?s$/.test(m.goAway.timeLeft)?Number(m.goAway.timeLeft.slice(0,-1)):10;
   this.rotation=setTimeout(()=>this.recover(epoch,true,false,true),Math.max(0,seconds*1000-500));
  }
 }
 private send(value:unknown):boolean{
  if(this.socket?.readyState!==1)return false;
  try{this.socket.send(JSON.stringify(value));return true;}catch{this.recover(this.epoch);return false;}
 }
 private recover(epoch:number,immediate=false,rateLimited=false,preserveOutput=false){
  if(!this.running||epoch!==this.epoch)return;
  // A failed resumed setup must not poison every subsequent connection.
  if(!this.ready&&this.resuming)this.handle=undefined;
  ++this.epoch;this.ready=false;clearTimeout(this.deadline);clearTimeout(this.stable);clearTimeout(this.rotation);
  const socket=this.socket;this.socket=undefined;try{socket?.close();}catch{/* already disconnected */}
  this.event({type:'reconnecting',...(preserveOutput?{preserveOutput:true}:{})});
  const ceiling=rateLimited?30000:10000;
  const delay=immediate?0:Math.min((rateLimited?1000:250)*2**this.attempt+Math.random()*250,ceiling);
  this.attempt=Math.min(this.attempt+1,7);
  const nextEpoch=this.epoch;this.retry=setTimeout(()=>{if(this.running&&nextEpoch===this.epoch)this.connect(preserveOutput);},delay);
 }
 private fail(text:string){this.stop();this.event({type:'error',text});}
 stop(){this.running=false;this.ready=false;++this.epoch;clearInterval(this.pump);clearTimeout(this.retry);clearTimeout(this.deadline);clearTimeout(this.stable);clearTimeout(this.rotation);try{this.socket?.close();}catch{/* already disconnected */}this.socket=undefined;this.queue=[];this.handle=undefined;this.config=undefined;this.attempt=0;}
}
export function measurePCM(base64:string){const raw=atob(base64);let sum=0;for(let i=0;i+1<raw.length;i+=2){let s=raw.charCodeAt(i)|(raw.charCodeAt(i+1)<<8);if(s>=32768)s-=65536;sum+=(s/32768)**2;}const rms=Math.sqrt(sum/Math.max(1,raw.length/2));return {db:Math.max(-96,20*Math.log10(Math.max(rms,1e-12))),level:Math.min(1,rms*5)};}
