# Flutter Live design

2026-11-04. The user selected the new **Linear** style from Atlas Design Pack.
The app stays Tauri + Svelte. Use the actual `@imfacto/svelte` Linear provider,
Button, Input, Select and Tabs from commit
`765b3c44515a59578347c595bfefaff24b19f694` (see `vendor/README.md`).

Default dark: near-black surfaces, off-white text, hairline dividers. One lime
primary action per screen. Hierarchy uses spacing, tracking and weights 400–600.
No heavy shadows or decorative gradients. Light and OS-following modes are also
supported. Use provider semantic tokens and the user's chosen font/size globally,
including portaled menus. The app uses its own Dash assets, not Linear logos.

Keep two modes and no history: current conversation, fixed-direction presentation
overlay. The current translation is the focal content. Dash remains a companion.
Retain hanbok, gat and dancheong and the existing 8 animated clips.

Appearance settings preview changes immediately; Apply saves only whitelisted
appearance properties locally, Cancel restores the prior state. Credentials and
transcripts must never enter that storage record. The independent overlay gets
font, theme and size through the caption event and expands for large text.

The user requested Stageshow (https://benji.org/stageshow). Its craft, visual
hierarchy and system-story choreography guide the actual Svelte interface and
presentation preview. Use existing product components, not a React app rewrite.
The preview tells one 8-second story: source speech appears, translation follows,
then the completed result holds. Reduced motion shows the final frame immediately.
See `docs/design-rehearsal.md` for the reference and review evidence.

Review at 900×760 and 680×600, light/dark, maximum typography. Workspace scrolls;
bottom actions remain accessible. Do not call a screenshot or unit fixture proof
of actual Gemini translation quality.
