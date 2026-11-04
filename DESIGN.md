# Flutter Live design

2026-11-04. Tauri + Svelte migration. The user's selected theme is Hansol.

Use the actual Atlas Design Pack `@imfacto/svelte` provider with `design="hansol"`
and `mode="light"`, including Button, Input, Select and Tabs. The pinned upstream
commit and local dependency preparation are in `vendor/README.md`.

White workspace, quiet gray chrome, charcoal text, restrained blue action. Keep
one primary action in the bottom control bar. Use semantic pack tokens, Noto Sans
KR, compact controls, subtle separators, and no decorative gradients or dashboard
cards. Respect keyboard focus and reduced motion.

The app has two modes, no history view: conversation (current translation and
original), and caption overlay (dark translucent bar on a presentation). Model
and audio settings have explicit apply/cancel. A key is masked and memory-only.

Retain the approved 2D Dash artwork: hanbok, gat and dancheong, 8 animation clips.
Dash is a contextual companion, not a replacement for the translated text.
The independent overlay intentionally uses dark high-contrast caption styling.

Review at 900×760 and minimum 680×600. Settings and long captions scroll inside
the workspace; bottom controls stay visible. Preview must be labeled as sample
content and must not record or call Gemini.
