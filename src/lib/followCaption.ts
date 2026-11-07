/** Follow new caption lines without trimming or interpreting the literal text. */
export function followCaption(node: HTMLElement, _text: string) {
 let frame: number | undefined;
 let destroyed = false;
 const follow = () => {
  if (destroyed) return;
  if (frame !== undefined) cancelAnimationFrame(frame);
  frame = requestAnimationFrame(() => {
   frame = undefined;
   node.scrollTop = Math.max(0, node.scrollHeight - node.clientHeight);
  });
 };
 const resize = new ResizeObserver(follow);
 resize.observe(node);
 // Font substitution can reflow text without changing the bounded viewport.
 document.fonts?.addEventListener('loadingdone', follow);
 follow();
 return {
  update(_text: string) { follow(); },
  destroy() {
   destroyed = true;
   resize.disconnect();
   document.fonts?.removeEventListener('loadingdone', follow);
   if (frame !== undefined) cancelAnimationFrame(frame);
  },
 };
}
