<script lang="ts">
 import {onMount} from 'svelte';
 let {skin='hanbok',clip='idle',size=200,animate=false}:{skin?:string;clip?:string;size?:number;animate?:boolean}=$props();
 let frame=$state(0);let reduced=$state(false);
 onMount(()=>{const q=matchMedia('(prefers-reduced-motion: reduce)');reduced=q.matches;const changed=()=>reduced=q.matches;q.addEventListener('change',changed);return()=>q.removeEventListener('change',changed)});
 $effect(()=>{frame=0;if(!animate||reduced)return;const timer=setInterval(()=>frame=(frame+1)%24,1000/12);return()=>clearInterval(timer)});
</script>
<div class="dash" role="img" aria-label={`${skin==='gat'?'갓':skin==='dancheong'?'단청':'한복'} 의상의 Dash`} style:width={`${size}px`} style:height={`${size}px`} style:background-image={`url('/dash/${skin}/${clip}.png')`} style:background-position={`${(frame%6)*20}% ${Math.floor(frame/6)*100/3}%`}></div>
<style>.dash{flex-shrink:0;background-size:600% 400%;background-repeat:no-repeat;contain:paint;}</style>
