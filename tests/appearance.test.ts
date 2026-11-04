import {expect,it} from 'vitest';
import {appearanceKey,defaults,normalizeAppearance,readAppearance,writeAppearance,captionHeight} from '../src/lib/appearance';
import {previewFrame} from '../src/lib/preview';
it('persists only appearance fields, never API credentials or transcripts',()=>{
 let saved='';expect(writeAppearance({setItem:(key,value)=>{expect(key).toBe(appearanceKey);saved=value}},{...defaults,theme:'light',key:'do-not-store',original:'private speech'})).toBe(true);
 expect(JSON.parse(saved)).toEqual({...defaults,theme:'light'});expect(saved).not.toContain('do-not-store');expect(saved).not.toContain('private speech');
 expect(readAppearance({getItem:()=>saved})).toEqual({...defaults,theme:'light'});
});
it('recovers corrupt storage and bounds sizes rather than breaking the layout',()=>{
 expect(readAppearance({getItem:()=>'{bad'})).toEqual(defaults);
 expect(normalizeAppearance({theme:'unknown',font:'injected',uiScale:400,captionSize:-3})).toEqual({...defaults,uiScale:130,captionSize:18});
 expect(normalizeAppearance({uiScale:NaN,captionSize:Infinity})).toEqual(defaults);
 expect(writeAppearance({setItem:()=>{throw Error('denied')}},defaults)).toBe(false);
});
it('grows the overlay for two translated lines plus original and controls',()=>{
 for(const size of [18,24,36,48])expect(captionHeight(size)).toBeGreaterThanOrEqual(92+size*2.8+Math.max(13,size*.6)*1.5);
 expect(captionHeight(48)).toBeGreaterThan(captionHeight(24));
});
it('previews the selected direction and holds its completed result',()=>{
 const start=previewFrame(0,'en','ko'),middle=previewFrame(3500,'en','ko'),end=previewFrame(9000,'en','ko');
 expect(start.translation).toBe('');expect(middle.translation.length).toBeGreaterThan(0);expect(end.original).toBe('Building new possibilities, together.');expect(end.translation).toBe('함께 만드는 새로운 가능성.');expect(end.done).toBe(true);
 expect(previewFrame(12000,'en','ko')).toEqual(end);
 expect(previewFrame(0,'ja','zh',true)).toMatchObject({translation:'携手创造新的可能。',clip:'idle',done:true});
});
