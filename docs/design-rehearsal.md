# Linear / Stageshow design review

## Brief

Use the user's actual Atlas Linear style on a functioning Svelte macOS interpreter.
Provide adjustable theme/font/text size. The translation and its reading order
lead; Dash keeps the app's Flutter event identity. Keep one primary action.

Stageshow source: https://github.com/benjitaylor/skills/tree/main/stageshow
Read SKILL.md, craft.md and review.md. Relevant references: the dark Linear study
(surface steps and restrained emphasis), system-story choreography and changing
text in place. The existing design pack owns actual controls; the React kit is
not added to this Svelte product.

## Preview story

900×760 desktop app, minimum 680×600. One user-triggered preview, not a looping
marketing hero. Over 8 seconds: source speech is revealed, translation follows,
Dash shifts from sing to speak to celebrate, then the complete translation holds.
A new playback starts only when the user presses preview again. No fabricated
mouse cursor. The selected language pair determines both sample sentences.
Reduced motion uses the completed poster immediately.

## Review evidence

- CUA browser renders at 900×760: Linear dark, light, typography 130% / 48px.
- CUA minimum 680×600 render and persisted serif font after reload.
- Cancel restored dark, 100%, 24px. Apply/reload preserved chosen font.
- Code tests cover preference whitelist (no key/transcript), corrupt storage,
  bounded sizes, overlay sizing, selected-language samples and reduced motion.
- Native Debug app: 48px preference survived restart; the overlay grew to
  900×270 and displayed two translated lines plus the original without clipping.
  Restored default appearance after verification.
- Native captures: `verification/linear-presentation.jpg`,
  `verification/linear-settings.jpg`, `verification/linear-overlay-48px.jpg`.
- Svelte check: 0 errors / 0 warnings. All 23 tests passed. Native Debug bundle
  build passed. Impeccable static detector returned no findings.
- Reviewed text hierarchy, controls, spacing and contrast. Range thumbs use
  neutral ink so the primary action retains the main lime emphasis.

The Stageshow Playwright filming scripts and their automatic rehearsal gate were
not executed; screenshots use this session's supported CUA tooling. This is not
a claim of passing its film gate or of frame-by-frame video verification.
