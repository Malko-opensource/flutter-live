# Live stream waiting and recovery

The client remains active through silence. Silence is not treated as a failed connection, and no artificial speech/text ping is sent. The native microphone path still emits 20 ms PCM chunks regardless of their level; the volume threshold only changes the character animation.

## Recovery policy

- Recoverable socket failures retry until the user stops, rather than permanently stopping after six attempts. The first retry waits 250–500 ms, then exponential backoff is capped at 10 seconds. Repeated rate-limit responses use a 30-second cap. Authentication/protocol rejection remains actionable rather than being retried forever.
- Audio is removed from the application queue only after WebSocket send succeeds. The queue holds at most 100 chunks and expires anything older than two seconds, favoring current speech over delayed playback after an outage.
- An open socket with queued audio and a non-progressing send buffer for five seconds is reconnected. No server response during silence is not evidence of failure.
- If previously sent PCM stops for at least one second, one `audioStreamEnd` flushes the server's cached input. The connection remains open; the next PCM message resumes the stream. Continuous silent PCM does not trigger this signal.
- `goAway` is advance notice. An active translation can finish until the advertised deadline; rotation happens at turn completion or shortly before that deadline, without ordinary backoff. Planned rotation preserves completed captions and already queued output audio. Unexpected failures still clear potentially stale playback.
- A non-resumable or rejected resume handle is discarded. A failed resumed setup falls back to a fresh session. Stale socket callbacks and retries cannot reactivate a stopped session.
- User stop/mode changes cancel pending microphone setup. A late setup rejection from an old session cannot overwrite a newer session. Native capture error text is assigned before the overlay error snapshot is sent.

The existing model, language instructions, automatic VAD, presentation `NO_INTERRUPTION`, and context compression remain unchanged. This patch does not switch to another translation model or tune speech thresholds without real speech evidence.

## Validation and limits

Fake-clock/socket tests cover 20 minutes without speech, later input, more than six failures, bounded retry delays, rate limiting, stale callbacks, setup timeout, planned rotation, invalid handles, send exceptions, bounded/fresh buffering, capture pause/resume, stalled send buffers and stop cancellation. Session tests cover silence, capture preservation, planned output preservation, native error visibility and asynchronous start/stop races.

These are deterministic local tests, not a live Gemini or microphone test. They do not establish end-to-end translation latency or audio quality. Already-sent audio may be lost on disconnect because server consumption is not acknowledged per chunk by the protocol used here. Outages longer than the two-second queue budget discard old input intentionally. A fresh session may lose prior context. No zero-loss, gap-free, or instantaneous interpretation guarantee is made.

Hardware removal, denied permissions and native system-audio errors still require the indicated device/permission fix. macOS 13 cannot disable hidden webview throttling, so keep the main window visible on that version.

If an older build is stuck active, use **일시 정지 → 통역 재개** to start a fresh connection. If it shows a terminal device/permission error, correct that issue and select **통역 시작**.

Official references:
- [Session lifetime, compression, resumption and goAway](https://ai.google.dev/gemini-api/docs/live-api/session-management)
- [Automatic VAD and paused audio streams](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
- [Live WebSocket protocol](https://ai.google.dev/api/live)
