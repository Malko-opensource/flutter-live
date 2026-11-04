<script lang="ts">
 import {Select,SelectTrigger,SelectContent,SelectItem} from '@imfacto/svelte/select';
 let {value=$bindable(''),items,label,disabled=false,onchange}:{value?:string;items:{value:string;label:string}[];label:string;disabled?:boolean;onchange?:(value:string)=>void}=$props();
</script>
<Select type="single" {value} {items} {disabled} onValueChange={(v)=>{if(v!==null){value=v;onchange?.(v)}}}>
 <SelectTrigger aria-label={label} class="picker"><span>{items.find(i=>i.value===value)?.label??'연결 끊김'}</span></SelectTrigger>
 <SelectContent>{#each items as item}<SelectItem value={item.value}>{item.label}</SelectItem>{/each}</SelectContent>
</Select>
