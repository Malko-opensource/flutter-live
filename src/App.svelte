<script lang="ts">
 import {appearance,resolvedTheme,resolvedCaptionTheme,observeSystemTheme} from './lib/appearance.svelte';
 import {fontFamilies} from './lib/appearance';
 import {onMount} from 'svelte';import {DesignSystemProvider} from '@imfacto/svelte/core';import {Button} from '@imfacto/svelte/button';import {Tabs,TabsList,TabsTrigger} from '@imfacto/svelte/tabs';
 import {Settings2,ArrowLeftRight,ArrowRight,Mic,Monitor,Volume2,VolumeX,Play,Pause,Square,ArrowUpRight,Subtitles,MessagesSquare} from 'lucide-svelte';
 import Dash from './lib/Dash.svelte';import Picker from './lib/Picker.svelte';import Settings from './lib/Settings.svelte';import Overlay from './lib/Overlay.svelte';
 import {session,settings,languages,chooseLanguage,init,active,locked,status,languageStatus,start,stop,preview,setMode,setVoice,setVolume,showOverlay,hideOverlay,syncOverlay} from './lib/session.svelte';
 const overlay=new URLSearchParams(location.search).has('overlay');let page=$state('main');let settingsTab=$state('model');
 onMount(()=>{const cleanup=observeSystemTheme();if(!overlay)void init();return()=>{cleanup();if(!overlay)void stop()}});
 function openSettings(tab='model'){settingsTab=tab;page='settings'}
 function primary(){if(active())void stop('paused');else if(!settings.key)openSettings();else void start()}
 $effect(()=>{if(!overlay){session.clip;settings.skin;void syncOverlay()}});
 $effect(()=>{
  document.documentElement.style.setProperty('--app-font',fontFamilies[appearance.font]);
  document.documentElement.style.setProperty('--ui-scale',String(appearance.uiScale/100));
  document.documentElement.style.setProperty('--caption-size',`${appearance.captionSize}px`);
  document.documentElement.style.setProperty('--caption-original-size',`${Math.max(13,appearance.captionSize*.6)}px`);
  if(!overlay)void syncOverlay();
 });
</script>
<DesignSystemProvider design="linear" mode={overlay?resolvedCaptionTheme():resolvedTheme()} class={overlay?'overlay-provider':'app-provider'}>
 {#if overlay}<Overlay/>{:else}
 <div class="app-shell">
  <header class="titlebar" data-tauri-drag-region><span data-tauri-drag-region>Flutter Live</span><div class="titlebar-right">{#if page==='main'}<Button variant="ghost" size="icon-sm" aria-label="설정" onclick={()=>openSettings()}><Settings2 size={16}/></Button>{/if}</div></header>
  {#if page==='settings'}<Settings initialTab={settingsTab} onclose={()=>page='main'}/>{:else}
  <div class="workspace">
   <div class="mode-row"><Tabs value={session.mode} onValueChange={v=>void setMode(String(v))}><TabsList variant="line" aria-label="통역 화면"><TabsTrigger value="conversation"><MessagesSquare size={16}/>대화 화면</TabsTrigger><TabsTrigger value="overlay"><Subtitles size={16}/>자막 오버레이</TabsTrigger></TabsList></Tabs><span class="mode-hint">{session.mode==='conversation'?'양방향 통역':'프레젠테이션'}</span></div>
   <div class="language-row">
    <div class="language-field">{#if session.mode==='overlay'}<span class="language-label">원문 언어</span>{/if}<Picker label={session.mode==='overlay'?'원문 언어':'첫 번째 언어'} value={session.first} onchange={v=>chooseLanguage('first',v)} disabled={locked()} items={languages.map(l=>({value:l.code,label:l.label}))}/></div>
    {#if session.mode==='overlay'}<Button class="direction-swap" variant="ghost" size="icon-sm" aria-label="원문과 번역 언어 바꾸기" disabled={locked()} onclick={()=>{const first=session.first;session.first=session.second;session.second=first;session.detected=''}}><ArrowRight size={16}/></Button>{:else}<ArrowLeftRight size={16}/>{/if}
    <div class="language-field">{#if session.mode==='overlay'}<span class="language-label">번역 언어</span>{/if}<Picker label={session.mode==='overlay'?'번역 언어':'두 번째 언어'} value={session.second} onchange={v=>chooseLanguage('second',v)} disabled={locked()} items={languages.map(l=>({value:l.code,label:l.label}))}/></div>
    <span class="auto-label" role="status">{languageStatus()}</span>
   </div>
   {#if session.notice}<p class="help workspace-notice" role="status">{session.notice}</p>{/if}
   <main class:overlay-mode={session.mode==='overlay'}>
   {#if session.mode==='conversation'}
    <section class="conversation" aria-label="현재 대화"><Dash size={210} skin={settings.skin} clip={session.clip} animate={active()||session.phase==='preview'}/>
     <div class:has-caption={!!session.translation} class="conversation-copy"><h1 aria-live="polite">{session.translation||(session.phase==='preview'?'번역을 준비하고 있어요':active()?'말씀해 주세요':'대화를 시작해 보세요.')}</h1><p>{session.original||'두 언어를 선택하고, 편하게 말씀하세요.'}</p></div>
     <div class="status" class:failed={session.phase==='error'} role="status"><span class:live={active()}></span>{status()}</div>
     {#if session.phase==='idle'||session.phase==='error'}<Button variant="text" size="sm" onclick={preview}><Play size={13}/>디자인 미리보기</Button>{/if}
    </section>
   {:else}
    <section class="overlay-workspace"><div class="section-heading"><h1>발표는 그대로, 자막은 내 언어로.</h1><p>원문과 번역 언어를 지정하고 자막을 띄우세요.</p></div>
     <div class="presentation-preview" aria-label="오버레이 미리보기"><div class="preview-slide"><span>Flutter Meetup</span><p>Build beautiful apps.</p><div class="slide-lines"><i></i><i></i><i></i></div></div><div class="preview-caption" data-caption-theme={resolvedCaptionTheme()}><Dash size={96} skin={settings.skin} clip={session.clip} animate={active()||session.phase==='preview'}/><div><span>{session.phase==='preview'?'디자인 미리보기':`${session.first.toUpperCase()} → ${session.second.toUpperCase()}`}</span><strong>{session.translation||'번역 자막이 여기에 표시됩니다.'}</strong><p>{session.original||'현재 발화만 표시합니다.'}</p></div></div></div>
     <div class="overlay-actions"><Button variant="secondary" onclick={()=>showOverlay(true)}>자막 띄우고 창 숨기기<ArrowUpRight size={16}/></Button>{#if session.overlay}<Button variant="text" onclick={hideOverlay}>자막 숨기기</Button>{/if}<Button variant="text" onclick={preview}>디자인 미리보기</Button></div><p class="help">메뉴바에서 Flutter Live 창을 다시 열 수 있습니다.</p><div class="status" role="status"><span class:live={active()}></span>{status()}</div>
    </section>
   {/if}
   </main>
   {#if session.error&&session.phase!=='error'}<p class="error workspace-error" role="alert">{session.error}</p>{/if}
   <footer class="control-bar"><div class="input-control"><Button variant="ghost" size="icon" aria-label="입력 장치 설정" onclick={()=>openSettings('audio')}>{#if settings.source==='system'}<Monitor size={18}/>{:else}<Mic size={18}/>{/if}</Button><meter min="0" max="1" value={session.level} aria-label="마이크 입력 크기"></meter></div><div class="volume-control"><Button variant="ghost" size="icon" aria-label={session.voice?'번역 음성 끄기':'번역 음성 켜기'} onclick={()=>setVoice(!session.voice)}>{#if session.voice}<Volume2 size={18}/>{:else}<VolumeX size={18}/>{/if}</Button><input type="range" min="0" max="1" step="0.01" aria-label="번역 음량" value={session.volume} disabled={!session.voice} oninput={e=>setVolume(Number(e.currentTarget.value))}/></div><div class="primary-controls">{#if active()||session.phase==='paused'||session.phase==='preview'}<Button variant="ghost" size="icon" aria-label="통역 종료" onclick={()=>stop()}><Square size={16}/></Button>{/if}<Button size="lg" onclick={primary}>{#if active()}<Pause size={16}/>{:else}<Play size={16}/>{/if}{active()?'일시 정지':session.phase==='paused'?'통역 재개':'통역 시작'}</Button></div></footer>
  </div>{/if}
 </div>{/if}
</DesignSystemProvider>
