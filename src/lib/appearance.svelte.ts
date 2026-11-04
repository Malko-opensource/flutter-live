import {defaults,readAppearance,writeAppearance,normalizeAppearance,type Appearance} from './appearance';
function initial(){if(typeof window==='undefined')return {...defaults};try{return readAppearance(localStorage)}catch{return {...defaults}}}
export const appearance=$state<Appearance>(initial());
export const systemStyle=$state({dark:false});
export function resolvedTheme(){return appearance.theme==='system'?(systemStyle.dark?'dark':'light'):appearance.theme}
export function resolvedCaptionTheme(){return appearance.captionTheme==='app'?resolvedTheme():appearance.captionTheme}
export function setAppearance(value:unknown){Object.assign(appearance,normalizeAppearance(value))}
export function persistAppearance(){try{return writeAppearance(localStorage,appearance)}catch{return false}}
export function observeSystemTheme(){const query=matchMedia('(prefers-color-scheme: dark)');const changed=()=>systemStyle.dark=query.matches;changed();query.addEventListener('change',changed);return()=>query.removeEventListener('change',changed)}
