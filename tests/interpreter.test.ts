import {expect,it} from 'vitest';
import {selectLanguage,supportedLanguages,detectedLanguage,interpreterInstruction} from '../src/lib/interpreter';
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

it('requests plain speech without stripping markup that is spoken content in either mode',()=>{
 for(const mode of ['conversation','presentation'] as const){
  const instruction=interpreterInstruction({mode,first:'Korean',second:'English',firstCode:'ko',secondCode:'en'});
  expect(instruction).toContain('Use plain translated speech');
  expect(instruction).toContain('Do not add XML, HTML, SSML or Markdown wrappers');
  expect(instruction).toContain('Preserve literal code or markup when it is itself part of the speech content');
 }
});
