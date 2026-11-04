import {detectedLanguage,supportedLanguages,selectLanguage} from './interpreter';
import {invoke,isTauri} from '@tauri-apps/api/core';
import {listen,emitTo} from '@tauri-apps/api/event';
import {getCurrentWindow} from '@tauri-apps/api/window';
import {LiveClient,measurePCM,type LiveEvent} from './live';
export type Device={uid:string;name:string;isDefault:boolean};
export type Skin='hanbok'|'gat'|'dancheong';
export type Phase='idle'|'preview'|'connecting'|'listening'|'translating'|'reconnecting'|'paused'|'error';
export const languages=supportedLanguages;
export function chooseLanguage(side:'first'|'second',code:string){if(locked())return;Object.assign(session,selectLanguage(session.first,session.second,side,code));session.detected='';}
export const settings=$state({key:'',model:'gemini-3.8-live',source:'microphone',uid:'',skin:'hanbok' as Skin,threshold:-18});
export const session=$state({mode:'conversation',first:'ko',second:'en',phase:'idle' as Phase,original:'',translation:'',detected:'',error:'',notice:'',voice:true,volume:.7,devices:[] as Device[],testing:false,level:0,db:-96,chunks:0,clip:'idle',overlay:false});
let initialized=false,capture=false,finishedInput=false,finishedOutput=false,timer:ReturnType<typeof setInterval>|undefined,quiet:ReturnType<typeof setTimeout>|undefined;
let committedInput='';let loudMs=0;const client=new LiveClient(onLive);
export function active(){return ['connecting','listening','translating','reconnecting'].includes(session.phase)}
export function locked(){return active()||session.phase==='paused'}
export function languageStatus(){if(session.mode==='overlay')return '번역 방향 고정';return session.phase==='preview'?'예시 자막':session.detected?`${languages.find(l=>l.code===session.detected)?.label} 감지`:active()?'언어 감지 대기':'언어 자동 감지'}
export function status(){return ({idle:'통역 준비',preview:'디자인 미리보기 · 실제 통역이 아닙니다',connecting:'Gemini에 연결 중',listening:'듣고 있어요',translating:'통역 중',reconnecting:'연결 재시도 중 · 일부 음성이 누락될 수 있어요',paused:'일시 정지',error:session.error})[session.phase]}
export async function audio(command:Record<string,unknown>){if(!isTauri())throw new Error('오디오 기능은 macOS 앱에서 사용할 수 있습니다.');await invoke('audio_command',{command});}
export async function refreshDevices(){if(isTauri())await audio({op:'devices'});}
export async function init(){if(initialized||!isTauri())return;initialized=true;await listen<any>('audio',e=>{
 const m=e.payload;if(m.type==='devices'){session.devices=m.devices;return;}
 if(m.type==='error'){void fail(m.message);return;}
 if(m.type==='output-error'){session.voice=false;session.error=m.message;return;}
 if(m.type==='pcm'&&(session.testing||capture&&active())){
  const v=measurePCM(m.data);session.db=v.db;session.level=v.level;session.chunks++;
  if(!session.testing){client.audio(m.data);if(v.db>settings.threshold)loudMs+=20;else loudMs=0;if(v.db>-38){session.clip=loudMs>=100?'megaphone':'sing';clearTimeout(quiet);quiet=setTimeout(()=>session.clip='listen',450);}}
 }
 });await listen('stop',()=>void stop());await listen('overlay-ready',()=>void syncOverlay());await listen('overlay-hidden',()=>session.overlay=false);await refreshDevices();}
export function snapshot(){return {original:session.original,translation:session.translation,label:`${languages.find(l=>l.code===session.first)?.label} ${session.mode==='overlay'?'→':'↔'} ${languages.find(l=>l.code===session.second)?.label} · ${languageStatus()}`,skin:settings.skin,clip:session.clip,animate:active()||session.phase==='preview',preview:session.phase==='preview'};}
export async function syncOverlay(){if(isTauri())await emitTo('overlay','caption',snapshot());}
async function onLive(e:LiveEvent){
 switch(e.type){
  case 'connecting':session.phase='connecting';break;
  case 'reconnecting':session.phase='reconnecting';session.clip='reconnect';session.original='';session.translation='';session.detected='';committedInput='';finishedInput=false;finishedOutput=false;await safeAudio({op:'clear'});break;
  case 'ready':session.phase='listening';session.clip='listen';if(!capture){capture=true;try{await audio({op:'volume',value:session.voice?session.volume:0});await audio({op:'start',source:settings.source,uid:settings.uid});}catch{await fail('오디오를 시작하지 못했습니다. macOS 앱에서 다시 시도해 주세요.');}}break;
  case 'interim':
  case 'input':
   if(finishedInput){committedInput='';session.original='';session.detected='';finishedInput=false;}
   if(e.languageCode!==undefined)session.detected=detectedLanguage(e.languageCode,session.first,session.second);
   if(e.type==='interim'){session.original=(committedInput+(e.text??'')).slice(-6000);}
   else {committedInput=(committedInput+(e.text??'')).slice(-6000);session.original=committedInput;finishedInput=!!e.finished;}
   break;
  case 'output':if(finishedOutput){session.translation='';finishedOutput=false;}session.translation=(session.translation+(e.text??'')).slice(-6000);session.phase='translating';if(session.clip!=='sing'&&session.clip!=='megaphone')session.clip='speak';break;
  case 'audio':if(session.voice)await safeAudio({op:'play',data:e.data});break;
  case 'interrupted':await safeAudio({op:'clear'});finishedOutput=true;session.phase='listening';break;
  case 'complete':finishedInput=true;finishedOutput=true;session.phase='listening';session.clip='listen';break;
  case 'error':await fail(e.text??'연결 오류');break;
 }void syncOverlay();
}
async function safeAudio(command:Record<string,unknown>){if(isTauri())await audio(command).catch(()=>{});}
export async function stop(phase:Phase='idle'){
 client.stop();clearInterval(timer);clearTimeout(quiet);capture=false;session.testing=false;session.level=0;session.db=-96;session.chunks=0;session.clip='idle';session.detected='';committedInput='';loudMs=0;session.phase=phase;
 await safeAudio({op:'stop'});await safeAudio({op:'clear'});if(phase==='idle'){session.notice='';session.original='';session.translation='';session.error='';}void syncOverlay();
}
async function fail(message:string){await stop('error');session.error=message;}
export async function start(){if(active())return;await stop();if(!settings.key.trim()){session.error='설정에서 Gemini API 키를 입력해 주세요.';return;}finishedInput=false;finishedOutput=false;client.start({mode:session.mode==='overlay'?'presentation':'conversation',key:settings.key.trim(),model:settings.model.trim(),firstCode:session.first,secondCode:session.second,first:languages.find(l=>l.code===session.first)!.name,second:languages.find(l=>l.code===session.second)!.name});}
export async function microphoneTest(uid:string){if(locked())return;await stop();session.testing=true;try{await audio({op:'start',source:'microphone',uid});}catch{await fail('마이크 테스트는 macOS 앱에서 사용할 수 있습니다.');}}
export async function preview(){await stop();session.phase='preview';session.original='Flutter 밋업에 오신 것을 환영합니다!';session.translation='Welcome to our Flutter meetup!';const clips=['wave','celebrate','sing','megaphone','listen','speak','idle','reconnect'];let index=0;session.clip=clips[0];timer=setInterval(()=>{session.clip=clips[++index%clips.length];void syncOverlay();},3500);void syncOverlay();}
export async function setMode(mode:string){if(mode===session.mode)return;const wasLocked=locked();if(wasLocked)await stop();session.mode=mode;session.detected='';if(wasLocked)session.notice='모드가 변경됐습니다. 언어를 확인하고 통역을 다시 시작해 주세요.';session.voice=mode==='conversation';await safeAudio({op:'volume',value:session.voice?session.volume:0});if(!session.voice)await safeAudio({op:'clear'});}
export async function setVoice(value:boolean){session.voice=value;await safeAudio({op:'volume',value:value?session.volume:0});if(!value)await safeAudio({op:'clear'});}
export async function setVolume(value:number){session.volume=value;await safeAudio({op:'volume',value:session.voice?value:0});}
export async function showOverlay(hide=false){if(!isTauri()){session.error='자막 오버레이는 macOS 앱에서 사용할 수 있습니다.';return;}await invoke('show_overlay',{visible:true});session.overlay=true;await syncOverlay();if(hide)await getCurrentWindow().hide();}
export async function hideOverlay(){if(isTauri())await invoke('show_overlay',{visible:false});session.overlay=false;}
