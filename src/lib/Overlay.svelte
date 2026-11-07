<script lang="ts">
 import {appearance,setAppearance,resolvedCaptionTheme} from './appearance.svelte';
 import {captionHeight} from './appearance';
 import {onMount} from 'svelte';import {isTauri,invoke} from '@tauri-apps/api/core';import {listen,emitTo} from '@tauri-apps/api/event';
 import {X,Settings2} from 'lucide-svelte';import Dash from './Dash.svelte';
 let value=$state({phase:'idle',status:'통역 준비',translation:'',original:'',label:'한국어 ↔ English',skin:'hanbok',clip:'idle',animate:false,preview:false,appearance:{...appearance}});
 onMount(()=>{document.body.classList.add('overlay-body');let cleanup:()=>void=()=>{};if(isTauri())void listen<typeof value>('caption',e=>{Object.assign(value,e.payload);if(e.payload.appearance)setAppearance(e.payload.appearance)}).then(fn=>{cleanup=fn;void emitTo('main','overlay-ready',{})});return()=>{cleanup();document.body.classList.remove('overlay-body')}});
 $effect(()=>{const height=captionHeight(appearance.captionSize);if(isTauri()){const timer=setTimeout(()=>void invoke('resize_overlay',{height}).catch(()=>{}),100);return()=>clearTimeout(timer)}});
</script>
<div class="native-caption" data-caption-theme={resolvedCaptionTheme()} role="region" aria-label="실시간 번역 자막" onpointerdown={e=>{if(e.target instanceof Element&&!e.target.closest('button')&&isTauri())void invoke('drag_overlay')}}>
 <Dash size={124} skin={value.skin} clip={value.clip} animate={value.animate}/><div class="caption-copy"><div class="caption-meta">{value.preview?'디자인 미리보기':`${value.label} · ${value.status}`}</div><p class="caption-translation" aria-live="polite">{value.phase==='error'?value.status:value.translation||value.status}</p><p class="caption-original">{value.original}</p></div>
 <div class="caption-actions"><button aria-label="메인 창 열기" onclick={()=>invoke('show_main')}><Settings2 size={16}/></button><button aria-label="자막 닫기" onclick={async()=>{await invoke('show_overlay',{visible:false});await emitTo('main','overlay-hidden',{})}}><X size={16}/></button></div>
</div>
