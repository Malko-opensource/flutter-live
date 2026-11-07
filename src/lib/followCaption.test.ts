import {afterEach, describe, expect, it, vi} from 'vitest';
import {followCaption} from './followCaption';

afterEach(() => vi.unstubAllGlobals());

describe('followCaption', () => {
 it('follows appended, replaced, and resized literal captions; cleans up on removal', () => {
  let next = 0;
  const frames = new Map<number, FrameRequestCallback>();
  vi.stubGlobal('requestAnimationFrame', (fn: FrameRequestCallback) => {frames.set(++next, fn); return next;});
  vi.stubGlobal('cancelAnimationFrame', (id: number) => frames.delete(id));
  const flush = () => { const pending = [...frames.values()]; frames.clear(); pending.forEach(fn => fn(0)); };
  let onResize: () => void = () => {};
  const disconnect = vi.fn();
  vi.stubGlobal('ResizeObserver', class { constructor(fn: () => void) {onResize = fn;} observe() {} disconnect = disconnect; });
  const fonts = new EventTarget();
  vi.stubGlobal('document', {fonts});
  const literal = '<section> literal &amp; `code` </section>\n마지막 문장';
  const node = {scrollTop: 0, scrollHeight: 200, clientHeight: 60, textContent: literal} as HTMLElement;
  const action = followCaption(node, literal);
  flush();
  expect(node.scrollTop).toBe(140);
  Object.assign(node, {scrollHeight: 400});
  action.update(literal + ' continued');
  action.update(literal + ' continued again');
  expect(frames.size).toBe(1);
  flush();
  expect(node.scrollTop).toBe(340);
  Object.assign(node, {clientHeight: 90});
  onResize(); flush();
  expect(node.scrollTop).toBe(310);
  Object.assign(node, {scrollHeight: 50});
  action.update('short replacement'); flush();
  expect(node.scrollTop).toBe(0);
  expect(node.textContent).toBe(literal);
  Object.assign(node, {scrollHeight: 300});
  fonts.dispatchEvent(new Event('loadingdone')); flush();
  expect(node.scrollTop).toBe(210);
  action.update('pending');
  action.destroy();
  expect(disconnect).toHaveBeenCalledOnce();
  expect(frames.size).toBe(0);
  onResize();
  fonts.dispatchEvent(new Event('loadingdone'));
  expect(frames.size).toBe(0);
 });
});
