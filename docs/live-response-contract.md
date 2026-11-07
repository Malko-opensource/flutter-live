# Gemini Live response contract and realtime limits

## Actual setup

Both modes use `gemini-3.8-live` over the JSON `BidiGenerateContent` WebSocket protocol. Output modality is AUDIO; readable translated speech comes from `serverContent.outputTranscription.text`. `modelTurn.parts.inlineData` carries PCM audio. Generic text parts are not combined with output transcription, since those parts need not represent spoken captions.

The official model/capability/API documents support the existing AUDIO setup, Kore voice, BCP-47 input language hints, empty output transcription config, automatic VAD, presentation NO_INTERRUPTION, context compression and session resumption. Language hints are not hard language constraints. Input is 16kHz PCM16 mono; output is 24kHz PCM16.

3.8 Live does not support structured outputs or a thinking_level setting. Proactive audio is permanently enabled, so a prompt cannot guarantee that every utterance elicits a translation. NO_INTERRUPTION prevents cancellation of current output; it is not a simultaneous-translation or latency guarantee.

The current VAD silence setting is 350ms with 100ms prefix padding. The official guide recommends testing 500–800ms silence thresholds; 350ms is legal but may split natural pauses. It remains unchanged rather than tuning without representative speech. The 20ms input chunk size is not end-to-end translation latency.

## Parsing boundaries

- The wire format is JSON. No XML, HTML or SSML wrapper is defined for transcription text.
- Validate field types and render transcription as literal text. Do not strip arbitrary angle-bracket content: `List<Widget>`, comparisons, quoted HTML and entities may be legitimate speech content.
- System instructions request plain translated speech without wrappers, while preserving literal code/markup when that is the content. This is prevention, not a formatting guarantee.
- Without a real offending example, no tag-specific parser or entity decoder is introduced. Unknown markup remains safe literal text; it is never executed as HTML.
- The current transcription schema documents `text` and `languageCode`, not `finished`. An explicit boolean finished field remains optional legacy compatibility, not a required contract.
- No universal delta-versus-cumulative guarantee was established for every 3.8 transcription message. The app preserves the existing chunk policy instead of heuristic deduplication.

## Ordering and display

WebSocket message order is preserved even when an earlier Blob requires asynchronous decoding; ordinary string messages retain a synchronous fast path. Within a message, final transcript text is processed before interruption/completion. Interrupted audio is discarded. Generation completion is not treated as turn completion or playback completion.

Input transcription has no ordering guarantee relative to model output/control messages. Model turn completion therefore no longer clears the rolling input transcript. Recent input remains bounded to 6000 characters, with no disk history. Output turns retain their own completion boundary. An asynchronous playback clear cannot overwrite the next turn's caption state.

## Bursty audio

The server may generate audio faster than realtime playback. The old two-second admission limit silently dropped valid output. Playback now schedules immediately under a finite 30-second / 4096-buffer budget (about 2.88MB float PCM plus overhead). This is a backlog ceiling, not a required initial wait. A slow consumer can still accumulate up to that much speech.

Overflow, invalid PCM or output failures cancel queued speech and explicitly disable voice output with an error, while input and captions continue. Re-enabling voice clears the failure latch. Interruptions and stop still clear queued output. Epoch/ticket bookkeeping prevents stale or repeated completion callbacks from corrupting the budget.

## Verification limits

Regression tests use mock WebSockets, fake clocks and silent native bookkeeping. Real Gemini authentication, recorded/live microphone speech, actual first-caption/first-audio latency, audio-device playback and long sessions have not been measured. No additional model/provider, speaker identification, microphone permission or data-sharing path is introduced.

Official references:
- [Gemini 3.8 Live model](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live)
- [Live API response/configuration schema](https://ai.google.dev/api/live)
- [Audio, transcription and VAD capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
- [Session management](https://ai.google.dev/gemini-api/docs/live-api/session-management)
- [Live API best practices](https://ai.google.dev/gemini-api/docs/live-api/best-practices)
