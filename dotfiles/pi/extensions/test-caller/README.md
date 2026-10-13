# Local WebRTC test caller

A second browser endpoint for CTM call testing without physical microphone access. It uses the official Twilio Voice JavaScript SDK, with a Web Audio microphone stream fed from local WAV/MP3 files or ElevenLabs synthesis. Audio stays on the local computer until WebRTC sends it into the call. No S3, public media hosting or tunnel is needed.

## Installation

Requires Node.js 24 or later, pnpm, and Pi. Install this package's dependencies before loading the extension:

```sh
cd ~/dotfiles/pi/extensions/test-caller
pnpm install --frozen-lockfile
```

This directory is self-contained, including its TTS engine and audio helper. Add its `index.ts` path to your Pi extension configuration, or link the directory into an existing Pi configuration's extensions directory. For a checkout at `~/peter-projects/pi-config`, with no existing `test-caller` directory:

```sh
ln -s ../../../dotfiles/pi/extensions/test-caller ~/peter-projects/pi-config/extensions/test-caller
```

Keep runtime configuration and credentials outside this package. The optional `ctm-dev` credential helper expects a local CTM Rails checkout at `~/work/ctm`; standalone installations can use the environment credential source.

## Setup

The extension does not provision resources or create live configuration. Copy the structure of `config.example.json` into your own `~/.pi/agent/test-caller.json` and configure an exact Twilio account, outgoing TwiML application, browser identity and target alias/number. Use a dedicated test account/application and API key where possible. The outgoing application must dial the configured target directly; caller commands never provide an arbitrary To parameter.

Create a dedicated Twilio TwiML Application with a fixed route to an approved test destination. For example, serve this TwiML through a TwiML Bin or an endpoint you control, substituting your own approved numbers:

```xml
<Response><Dial callerId="+15550000001" timeLimit="180" timeout="30"><Number>+15550000002</Number></Dial></Response>
```

Point the application at that route and set `target_number` to its fixed destination. Verify the deployed route before enabling calls. Never use CTM's normal agent outbound application. Route the CTM tracking number to the feature under test; a VoiceBot route exercises a different flow from an agent queue.

The application route must have a provider `<Dial timeLimit="180">` or a shorter bound matching your configured `maxCallSeconds`. Set `provider_time_limit_confirmed` to true only after checking that route. A local watchdog alone cannot bound a call after the browser loses connectivity.

The example prefers `credential_source: "ctm-dev"` with `ctm_account_id: 1`. Set `account_sid` to that exact local account's existing Twilio account SID. The read-only development Rails helper uses the account's existing Voice SDK API key and encrypted secret to sign the dedicated caller token. It checks the configured account, runs in a read-only transaction, and refuses the existing CTM outbound application so this caller uses its separate fixed route. It returns a signed token internally; key material is not displayed or copied into new credentials. The CTM development database and mise Rails toolchain must be available.

For standalone use, select `credential_source: "environment"` and name existing credential variables with `apiKeySidEnv` and `apiKeySecretEnv`. Defaults are `TEST_CALLER_TWILIO_API_KEY_SID` and `TEST_CALLER_TWILIO_API_KEY_SECRET`. They are read from the existing process environment or `~/.env` as data; secrets do not belong in the JSON. No implicit CTM master credential fallback exists. ElevenLabs speech uses the existing `ELEVENLABS_API_KEY` loader.

Call `caller_setup({})`, open its returned loopback URL locally, press **Start audio** to activate browser playback. This action can be automated; it does not request microphone access. Keep the page open while using the tools. The URL fragment contains a session access secret; do not share it. Setup does not dial a call. Without a valid configuration and API key it returns an explicit prerequisite error.

## Tools

```json
{"target":"ctm-test"}
```

Use this with `caller_dial`. It returns an opaque `call_id`; use that same ID for the remaining tools.

```json
{"call_id":"returned-call-id","text":"Hello, I need help changing my appointment."}
```

`caller_speak` synthesizes an ElevenLabs WAV, registers it with the authenticated local runtime, and feeds it into the caller's WebRTC microphone stream. A cache miss consumes ElevenLabs credits. The receiver must be verified separately with CTM's recording or transcript.

```json
{"call_id":"returned-call-id","path":"/absolute/path/inside/allowed/audio/speech.mp3"}
```

`caller_play` supports WAV and MP3 files inside `allowed_audio_directory`, which defaults to `~/.pi/agent/tts`. Set an explicit absolute directory when using your own local MP3 library. The existing TTS cache remains an allowed root when a custom library directory is configured. Paths are fenced after resolving symlinks; outside files and remote URLs are rejected. Files must be nonempty and at most 10 MiB. The browser also bounds decoded audio duration.

`caller_press_digits({"call_id":"...","digits":"12#w"})` sends SDK DTMF. Lowercase w represents a pause; uppercase W is rejected.

`caller_status({"call_id":"..."})` reports the owned browser call and persists observed terminal state. `caller_hangup({"call_id":"..."})` disconnects that owned call only. Status and hangup remain available while synthesis/playback runs.

A connected browser call can be a queue, IVR or VoiceBot. Every call receipt keeps `agent_connected: "unverified"`; audio receipts keep `call_received: "unverified"` and preserve playback completion or interruption separately from call status.

## Limits and recovery

The local client is trusted and connects with empty SDK parameters, so these tools cannot supply a different destination. Public Echo is not an adversarial fence against someone holding a Voice SDK token; use a server-controlled fixed route for that stronger boundary.

The extension permits one active call and defaults to five attempts per rolling 24 hours. Configuration can set the attempt limit from one to six. It persists attempts before dispatch and uses a process-safe file lock. An ambiguous dispatch is never retried automatically. Unknown or previous-session active records block further calls until checked or manually reconciled; inspect the configured account and provider call state before correcting records. Never remove a live session's lock.

Keep the caller browser heartbeat active. Lost controller connectivity and session shutdown are bounded by the configured provider route and the browser call watchdog. Local files are served only through opaque authenticated runtime IDs. API key secrets and Twilio access tokens are kept out of tool receipts; the local session URL is the one intentionally returned access credential.

## Verification

```sh
cd ~/dotfiles/pi/extensions/test-caller
pnpm test
pnpm typecheck
```

Tests use fake calls and local audio. No actual Twilio calls or purchases are performed by those tests. Real SDK registration, call routing and CTM reception need a configured browser test.
