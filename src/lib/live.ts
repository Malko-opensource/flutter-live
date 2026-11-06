import {interpreterInstruction,modeModels,type LanguagePair} from './interpreter';
export type LiveConfig=LanguagePair & {key:string};
export type LiveEvent={type:'ready'|'connecting'|'reconnecting'|'input'|'interim'|'output'|'audio'|'interrupted'|'complete'|'error';text?:string;data?:string;finished?:boolean;languageCode?:string};
export interface SocketLike {readyState:number;readonly bufferedAmount?:number;onopen:((e:Event)=>void)|null;onmessage:((e:MessageEvent)=>void)|null;onerror:((e:Event)=>void)|null;onclose:((e:CloseEvent)=>void)|null;send:(data:string)=>void;close:()=>void}
export function setup(config:LiveConfig,handle?:string){return {setup:{model:`models/${modeModels[config.mode]}`,generationConfig:{responseModalities:['AUDIO'],speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:'Kore'}}}},systemInstruction:{parts:[{text:interpreterInstruction(config)}]},inputAudioTranscription:{languageCodes:config.mode==='presentation'?[config.firstCode]:[config.firstCode,config.secondCode]},outputAudioTranscription:{},realtimeInputConfig:{automaticActivityDetection:{silenceDurationMs:350,prefixPaddingMs:100},activityHandling:'START_OF_ACTIVITY_INTERRUPTS'},sessionResumption:handle?{handle}:{},contextWindowCompression:{slidingWindow:{}}}}}
export class LiveClient {
 private socket?:SocketLike;private config?:LiveConfig;private epoch=0;private running=false;private ready=false;private attempt=0;private handle?:string;
 private queue:string[]=[];private retry?:ReturnType<typeof setTimeout>;private deadline?:ReturnType<typeof setTimeout>;private stable?:ReturnType<typeof setTimeout>;private pump?:ReturnType<typeof setInterval>;
 constructor(private event:(event:LiveEvent)=>void,private factory:(url:string)=>SocketLike=url=>new WebSocket(url)){}
 start(config:LiveConfig){this.stop();this.running=true;this.config=config;this.pump=setInterval(()=>{for(let i=0;i<4&&this.ready&&this.queue.length&&(this.socket?.bufferedAmount??0)<65536;i++)this.send({realtimeInput:{audio:{data:this.queue.shift(),mimeType:'audio/pcm;rate=16000'}}});},20);this.connect();}
 audio(data:string){if(this.running){this.queue.push(data);if(this.queue.length>100)this.queue.shift();}}
 get bufferedChunks(){return this.queue.length;}
 private connect(){
  if(!this.running||!this.config)return;const epoch=++this.epoch;this.ready=false;
  this.event({type:this.attempt?'reconnecting':'connecting'});
  try {const socket=this.factory(`wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${encodeURIComponent(this.config.key)}`);this.socket=socket;
   this.deadline=setTimeout(()=>this.recover(epoch),12000);
   socket.onopen=()=>{if(epoch===this.epoch)this.send(setup(this.config!,this.handle));};
   socket.onmessage=async e=>{try{const raw=e.data instanceof Blob?await e.data.text():e.data;if(epoch===this.epoch)this.receive(JSON.parse(raw),epoch);}catch{if(epoch===this.epoch)this.fail('서버 응답을 읽지 못했습니다. 다시 시작해 주세요.');}};
   socket.onerror=()=>this.recover(epoch);
   socket.onclose=e=>{if(epoch!==this.epoch)return;if([1003,1007,1008].includes(e.code))this.fail('연결이 거부됐습니다. API 키와 해당 키의 사용 권한을 확인해 주세요.');else this.recover(epoch);};
  }catch{this.recover(epoch);}
 }
 private receive(m:any,epoch:number){
  if(m.error){if([429,500,502,503,504].includes(m.error.code))this.recover(epoch);else this.fail('Gemini 요청이 거부됐습니다. API 키·사용 권한·사용 한도를 확인해 주세요.');return;}
  if(m.setupComplete!==undefined){clearTimeout(this.deadline);this.ready=true;this.stable=setTimeout(()=>this.attempt=0,30000);this.event({type:'ready'});}
  if(m.sessionResumptionUpdate?.resumable&&m.sessionResumptionUpdate.newHandle)this.handle=m.sessionResumptionUpdate.newHandle;
  const c=m.serverContent;
  if(c){
   if(c.interrupted)this.event({type:'interrupted'});
   if(c.inputTranscription)this.event({type:'input',text:c.inputTranscription.text??'',finished:!!c.inputTranscription.finished,languageCode:c.inputTranscription.languageCode});
   else if(c.interimInputTranscription)this.event({type:'interim',text:c.interimInputTranscription.text??'',languageCode:c.interimInputTranscription.languageCode});
   if(c.outputTranscription)this.event({type:'output',text:c.outputTranscription.text??'',languageCode:c.outputTranscription.languageCode});
   if(!c.interrupted)for(const p of c.modelTurn?.parts??[]){if(p.inlineData?.mimeType?.startsWith('audio/pcm')){const rate=/rate=(\d+)/.exec(p.inlineData.mimeType)?.[1];if(rate&&rate!=='24000'){this.fail('지원하지 않는 음성 출력 형식입니다. 앱 업데이트를 확인해 주세요.');return;}this.event({type:'audio',data:p.inlineData.data});}}
   if(c.turnComplete)this.event({type:'complete'});
  }
  if(m.goAway)this.recover(epoch);
 }
 private send(value:unknown){if(this.socket?.readyState===1){try{this.socket.send(JSON.stringify(value));}catch{this.recover(this.epoch);}}}
 private recover(epoch:number){
  if(!this.running||epoch!==this.epoch)return;++this.epoch;this.ready=false;clearTimeout(this.deadline);clearTimeout(this.stable);this.socket?.close();this.socket=undefined;
  if(this.attempt>=6){this.fail('연결을 복구하지 못했습니다. 네트워크를 확인하고 다시 시작해 주세요.');return;}
  this.event({type:'reconnecting'});const delay=Math.min(1000*2**this.attempt++,30000)+Math.random()*300;this.retry=setTimeout(()=>this.connect(),delay);
 }
 private fail(text:string){this.stop();this.event({type:'error',text});}
 stop(){this.running=false;this.ready=false;++this.epoch;clearInterval(this.pump);clearTimeout(this.retry);clearTimeout(this.deadline);clearTimeout(this.stable);this.socket?.close();this.socket=undefined;this.queue=[];this.handle=undefined;this.config=undefined;this.attempt=0;}
}
export function measurePCM(base64:string){const raw=atob(base64);let sum=0;for(let i=0;i+1<raw.length;i+=2){let s=raw.charCodeAt(i)|(raw.charCodeAt(i+1)<<8);if(s>=32768)s-=65536;sum+=(s/32768)**2;}const rms=Math.sqrt(sum/Math.max(1,raw.length/2));return {db:Math.max(-96,20*Math.log10(Math.max(rms,1e-12))),level:Math.min(1,rms*5)};}
