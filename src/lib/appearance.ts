export type Appearance = {
  theme: 'light' | 'dark' | 'system';
  font: 'linear' | 'system' | 'serif';
  uiScale: number;
  captionSize: number;
  captionTheme: 'dark' | 'light' | 'app';
};
export const appearanceKey='flutter-live.appearance.v1';
export const defaults:Appearance={theme:'dark',font:'linear',uiScale:100,captionSize:24,captionTheme:'dark'};
export const fontFamilies={
 linear:'"Inter Variable", "Noto Sans KR", "Apple SD Gothic Neo", sans-serif',
 system:'-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif',
 serif:'"AppleMyungjo", "Songti SC", "Hiragino Mincho ProN", Georgia, serif',
};
const bounded=(value:unknown,fallback:number,min:number,max:number)=>typeof value==='number'&&Number.isFinite(value)?Math.min(max,Math.max(min,Math.round(value))):fallback;
export function normalizeAppearance(value:unknown):Appearance {
 const p=(value&&typeof value==='object'?value:{}) as Partial<Appearance>;
 return {
  theme:['light','dark','system'].includes(p.theme??'')?p.theme!:defaults.theme,
  font:['linear','system','serif'].includes(p.font??'')?p.font!:defaults.font,
  uiScale:bounded(p.uiScale,defaults.uiScale,90,130),
  captionSize:bounded(p.captionSize,defaults.captionSize,18,48),
  captionTheme:['light','dark','app'].includes(p.captionTheme??'')?p.captionTheme!:defaults.captionTheme,
 };
}
export function readAppearance(storage:Pick<Storage,'getItem'>):Appearance {
 try{return normalizeAppearance(JSON.parse(storage.getItem(appearanceKey)??'null'))}catch{return {...defaults}}
}
export function writeAppearance(storage:Pick<Storage,'setItem'>,value:unknown):boolean {
 try{storage.setItem(appearanceKey,JSON.stringify(normalizeAppearance(value)));return true}catch{return false}
}
export function captionHeight(size:number){return Math.max(160,Math.ceil(92+size*2.8+Math.max(13,size*.6)*1.5))}
