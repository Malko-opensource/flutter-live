<script lang="ts">
 import {onMount,untrack} from 'svelte';
 import {Button} from '@imfacto/svelte/button';import {Input} from '@imfacto/svelte/input';
 import {Tabs,TabsList,TabsTrigger,TabsContent} from '@imfacto/svelte/tabs';
 import {ArrowLeft,Eye,EyeOff,Mic,Square,RefreshCw} from 'lucide-svelte';
 import Picker from './Picker.svelte';import Dash from './Dash.svelte';
 import {settings,session,locked,refreshDevices,microphoneTest,stop,syncOverlay,type Skin} from './session.svelte';
 let {onclose,initialTab='model'}:{onclose:()=>void;initialTab?:string}=$props();
 let draft=$state(untrack(()=>({...settings})));let tab=$state(untrack(()=>initialTab));let showKey=$state(false);let error=$state('');
 const devices=$derived([{value:'',label:`자동 · ${session.devices.find(d=>d.isDefault)?.name??'연결된 마이크 없음'}`},...session.devices.map(d=>({value:d.uid,label:d.name}))]);
 onMount(()=>{void refreshDevices();return()=>{if(session.testing)void stop()}});
 async function apply(){
  if(!locked()){
   if(/\s/.test(draft.key.trim())){error='API 키 안의 공백이나 줄바꿈을 지워 주세요.';tab='model';return;}
   if(!/^(models\/)?[a-zA-Z0-9._-]+$/.test(draft.model.trim())){error='사용할 Live 모델 ID를 입력해 주세요.';tab='model';return;}
   if(session.testing)await stop();Object.assign(settings,{...draft,key:draft.key.trim(),model:draft.model.trim()});
  }else{settings.skin=draft.skin;settings.threshold=draft.threshold;}
  void syncOverlay();onclose();
 }
 function close(){if(session.testing)void stop();onclose()}
</script>
<svelte:window onkeydown={e=>{if(e.key==='Escape')close()}}/>
<section class="settings-page">
 <header class="settings-heading"><Button variant="ghost" size="icon" aria-label="설정 닫기" onclick={close}><ArrowLeft size={18}/></Button><h1>설정</h1></header>
 <Tabs bind:value={tab} class="settings-tabs"><TabsList variant="line" aria-label="설정 분류"><TabsTrigger value="model">모델 연결</TabsTrigger><TabsTrigger value="audio">오디오 · 대쉬</TabsTrigger></TabsList>
 <div class="settings-scroll">
 <TabsContent value="model">
  <div class="section-heading"><h2>Gemini Live</h2><p>실시간 통역에 사용할 모델을 연결합니다.</p></div>
  {#if locked()}<p class="notice">통역을 종료하면 연결 설정을 변경할 수 있습니다.</p>{/if}
  <div class="field"><label for="api-key">API 키</label><Input id="api-key" type={showKey?'text':'password'} bind:value={draft.key} disabled={locked()} placeholder="Google AI Studio에서 발급한 키" autocomplete="off" spellcheck={false}>
   {#snippet trailing()}<Button variant="ghost" size="icon-sm" aria-label={showKey?'API 키 숨기기':'API 키 보기'} onclick={()=>showKey=!showKey}>{#if showKey}<EyeOff size={16}/>{:else}<Eye size={16}/>{/if}</Button>{/snippet}
  </Input><p class="help">키는 이번 실행에서만 사용하며 앱을 종료하면 지워집니다.</p></div>
  <div class="field"><label for="model-id">Live 모델 ID</label><Input id="model-id" bind:value={draft.model} disabled={locked()} spellcheck={false}/><p class="help">모델 접근 권한과 API 키는 통역 시작 시 확인합니다.</p></div>
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="settings-note"><span class="note-dot"></span><p>통역을 시작하면 선택한 오디오가 Gemini로 전송됩니다.<br/>현재 발화만 표시하며 대화 기록은 저장하지 않습니다.</p></div>
 </TabsContent>
 <TabsContent value="audio">
  <div class="section-heading"><h2>오디오 입력</h2><p>통역할 소리를 선택하고 입력 상태를 확인합니다.</p></div>
  <div class="field"><label for="source">입력 소스</label><Picker label="입력 소스" bind:value={draft.source} disabled={locked()||session.testing} items={[{value:'microphone',label:'마이크'},{value:'system',label:'시스템 오디오 · 발표 / 동영상'}]}/></div>
  {#if draft.source==='microphone'}
   <div class="field"><label for="microphone">사용할 마이크</label><div class="inline-field"><Picker label="사용할 마이크" bind:value={draft.uid} items={devices} disabled={locked()||session.testing}/><Button variant="ghost" size="icon" aria-label="마이크 목록 새로고침" onclick={refreshDevices}><RefreshCw size={16}/></Button></div><p class="help">블루투스·USB·유선 등 연결된 입력 장치를 사용합니다.</p></div>
   <div class="test-row"><Button variant="secondary" size="sm" disabled={locked()||!session.devices.length} onclick={()=>session.testing?stop():microphoneTest(draft.uid)}>{#if session.testing}<Square size={14}/>{:else}<Mic size={14}/>{/if}{session.testing?'테스트 중지':'마이크 테스트'}</Button><meter min="0" max="1" value={session.level} aria-label="마이크 입력 크기"></meter><span class="numeric">{session.testing?`${Math.round(session.db)} dBFS`:'입력 대기'}</span></div>
   <p class="help">{session.testing?(session.chunks?'입력 수신 중 · 저장하거나 서버로 보내지 않습니다.':'마이크 연결 중…'):'API 키 없이 입력 크기를 확인할 수 있습니다.'}</p>
  {:else}<p class="help">macOS 화면 및 시스템 오디오 녹음 권한이 필요합니다.</p>{/if}
  {#if session.error}<p class="error" role="alert">{session.error}</p>{/if}
  <div class="appearance-row"><div><h2>대쉬</h2><div class="field"><label for="costume">의상</label><Picker label="대쉬 의상" value={draft.skin} onchange={v=>draft.skin=v as Skin} items={[{value:'hanbok',label:'한복'},{value:'gat',label:'갓 · 두루마기'},{value:'dancheong',label:'단청 무대'}]}/></div></div><Dash size={128} skin={draft.skin} clip="wave"/></div>
  <div class="field"><label for="threshold">확성기 전환 <span class="numeric">{draft.threshold} dBFS</span></label><input id="threshold" type="range" min="-36" max="-6" step="1" bind:value={draft.threshold}/><p class="help">왼쪽으로 옮기면 더 작은 목소리에 반응합니다. 실제 공간의 소음 데시벨과는 다릅니다.</p></div>
 </TabsContent>
 </div></Tabs>
 <footer class="settings-footer"><span>변경한 내용은 적용 후 사용됩니다.</span><Button variant="text" onclick={close}>취소</Button><Button onclick={apply}>설정 적용</Button></footer>
</section>
