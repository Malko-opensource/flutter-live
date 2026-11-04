// Stageshow-inspired system story: speech arrives, translation follows, the result holds.
const samples:Record<string,string>={ko:'함께 만드는 새로운 가능성.',en:'Building new possibilities, together.',ja:'一緒に、新しい可能性を。',zh:'携手创造新的可能。'};
export function previewFrame(elapsed:number,first:string,second:string,reduced=false){
 const source=samples[first]??samples.ko,target=samples[second]??samples.en;
 const reveal=(text:string,progress:number)=>Array.from(text).slice(0,Math.ceil(Array.from(text).length*Math.max(0,Math.min(1,progress)))).join('');
 if(reduced)return {original:source,translation:target,clip:'idle',done:true};
 return {original:reveal(source,(elapsed+80)/2600),translation:reveal(target,(elapsed-1800)/3600),clip:elapsed<2600?'sing':elapsed<5400?'speak':elapsed<8000?'celebrate':'listen',done:elapsed>=8000};
}
