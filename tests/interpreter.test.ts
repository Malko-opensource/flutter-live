import {expect,it} from 'vitest';
import {selectLanguage,supportedLanguages,detectedLanguage} from '../src/lib/interpreter';
it('supports every directed pair among the four requested languages',()=>{
 for(const source of supportedLanguages)for(const target of supportedLanguages){
  if(source.code===target.code)continue;
  const first=selectLanguage('ko','en','first',source.code);
  const pair=selectLanguage(first.first,first.second,'second',target.code);
  expect(pair).toEqual({first:source.code,second:target.code});
 }
});
it('swaps either side rather than hiding English or creating an identical pair',()=>{
 expect(selectLanguage('ko','en','first','en')).toEqual({first:'en',second:'ko'});
 expect(selectLanguage('ko','en','second','ko')).toEqual({first:'en',second:'ko'});
 expect(selectLanguage('ko','en','first','es')).toEqual({first:'ko',second:'en'});
});
it('normalizes server language tags without guessing unsupported languages',()=>{
 expect(detectedLanguage('ko-KR','ko','en')).toBe('ko');
 expect(detectedLanguage('en-US','ko','en')).toBe('en');
 expect(detectedLanguage(undefined,'ko','en')).toBe('');
 expect(detectedLanguage('fr','ko','en')).toBe('');
});
