<script lang="ts">
 import {appearance,setAppearance,persistAppearance,resolvedCaptionTheme} from './appearance.svelte';
 import {defaults,type Appearance} from './appearance';
 import {onMount,untrack} from 'svelte';
 import {Button} from '@imfacto/svelte/button';import {Input} from '@imfacto/svelte/input';
 import {Tabs,TabsList,TabsTrigger,TabsContent} from '@imfacto/svelte/tabs';
 import {ArrowLeft,Eye,EyeOff,Mic,Square,RefreshCw} from 'lucide-svelte';
 import Picker from './Picker.svelte';import Dash from './Dash.svelte';
 import {settings,session,locked,refreshDevices,microphoneTest,stop,syncOverlay,type Skin} from './session.svelte';
 let {onclose,initialTab='model'}:{onclose:()=>void;initialTab?:string}=$props();
 const originalAppearance=untrack(()=>({...appearance}));let accepted=false;let appearanceError=$state('');
 let draft=$state(untrack(()=>({...settings})));let tab=$state(untrack(()=>initialTab));let showKey=$state(false);let error=$state('');
 const devices=$derived([{value:'',label:`자동 · ${session.devices.find(d=>d.isDefault)?.name??'연결된 마이크 없음'}`},...session.devices.map(d=>({value:d.uid,label:d.name}))]);
 onMount(()=>{void refreshDevices();return()=>{if(session.testing)void stop();if(!accepted)setAppearance(originalAppearance)}});
 async function apply(){
  if(!locked()){
   if(/\s/.test(draft.key.trim())){error='API 키 안의 공백이나 줄바꿈을 지워 주세요.';tab='model';return;}
   if(!/^(models\/)?[a-zA-Z0-9._-]+$/.test(draft.model.trim())){error='사용할 Live 모델 ID를 입력해 주세요.';tab='model';return;}
   if(!persistAppearance()){appearanceError='표시 설정을 저장하지 못했습니다. 다시 적용해 주세요.';tab='appearance';return;}
   if(session.testing)await stop();Object.assign(settings,{...draft,key:draft.key.trim(),model:draft.model.trim()});
  }else{if(!persistAppearance()){appearanceError='표시 설정을 저장하지 못했습니다.';tab='appearance';return;}settings.skin=draft.skin;settings.threshold=draft.threshold;}
  accepted=true;void syncOverlay();onclose();
 }
 function close(){if(session.testing)void stop();onclose()}
</script>
<svelte:window onkeydown={e=>{if(e.key==='Escape'&&!e.defaultPrevented)close()}}/>
<section class="settings-page">
 <header class="settings-heading"><Button variant="ghost" size="icon" aria-label="설정 닫기" onclick={close}><ArrowLeft size={18}/></Button><h1>설정</h1></header>
 <Tabs bind:value={tab} class="settings-tabs"><TabsList variant="line" aria-label="설정 분류"><TabsTrigger value="model">모델 연결</TabsTrigger><TabsTrigger value="audio">오디오 · 대쉬</TabsTrigger><TabsTrigger value="appearance">화면 · 자막</TabsTrigger></TabsList>
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
 <TabsContent value="appearance">
  <div class="section-heading"><h2>나에게 편한 화면</h2><p>변경 사항을 바로 확인하고 적용하면 다음 실행에도 유지됩니다.</p></div>
  <div class="appearance-fields">
   <div class="field"><label for="theme">화면 테마</label><Picker label="화면 테마" value={appearance.theme} onchange={v=>appearance.theme=v as Appearance['theme']} items={[{value:'dark',label:'어둡게'},{value:'light',label:'밝게'},{value:'system',label:'시스템 설정에 맞추기'}]}/></div>
   <div class="field"><label for="font">글꼴</label><Picker label="글꼴" value={appearance.font} onchange={v=>appearance.font=v as Appearance['font']} items={[{value:'linear',label:'Linear 기본 · Inter / Noto Sans KR'},{value:'system',label:'macOS 시스템'},{value:'serif',label:'명조'}]}/></div>
  </div>
  <div class="field"><label for="ui-scale">화면 글자 크기 <span class="numeric">{appearance.uiScale}%</span></label><input id="ui-scale" type="range" min="90" max="130" step="5" bind:value={appearance.uiScale}/></div>
  <div class="field"><label for="caption-size">번역 자막 크기 <span class="numeric">{appearance.captionSize}px</span></label><input id="caption-size" type="range" min="18" max="48" step="2" bind:value={appearance.captionSize}/><p class="help">대화 화면과 자막 오버레이에 함께 적용됩니다.</p></div>
  <div class="field"><label for="caption-theme">자막 배경</label><Picker label="자막 배경" value={appearance.captionTheme} onchange={v=>appearance.captionTheme=v as Appearance['captionTheme']} items={[{value:'dark',label:'어두운 배경'},{value:'light',label:'밝은 배경'},{value:'app',label:'화면 테마와 같게'}]}/></div>
  <div class="appearance-sample" data-caption-theme={resolvedCaptionTheme()} aria-label="자막 스타일 미리보기"><span>자막 미리보기</span><p>함께 만드는 새로운 가능성.</p><small>Building new possibilities, together.</small></div>
  {#if appearanceError}<p class="error" role="alert">{appearanceError}</p>{/if}
  <Button variant="text" size="sm" onclick={()=>setAppearance(defaults)}>표시 설정 초기화</Button>
 </TabsContent>
 </div></Tabs>
 <footer class="settings-footer"><span>{tab==='appearance'?'취소하면 이전 표시 설정으로 돌아갑니다.':'변경한 내용은 적용 후 사용됩니다.'}</span><Button variant="text" onclick={close}>취소</Button><Button onclick={apply}>설정 적용</Button></footer>
</section>
