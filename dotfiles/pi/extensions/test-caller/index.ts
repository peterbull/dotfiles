import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { CallerEngine } from "./engine.ts";
const emit = (value: unknown) => ({
    content: [{
            type: "text" as const,
            text: JSON.stringify(value, null, 2)
        }],
    details: value
});
export default function (pi: ExtensionAPI) {
    const caller = new CallerEngine();
    pi.on("session_shutdown", async () => {
        await caller.close();
    });
    pi.registerTool({
        name: "caller_setup",
        label: "Local WebRTC test caller setup",
        description: "Start the local-only caller page and report redacted prerequisites. Open the returned session URL locally and press Start audio. Does not provision Twilio resources or dial.",
        parameters: Type.Object({}),
        async execute() {
            return emit(await caller.setup());
        }
    });
    pi.registerTool({
        name: "caller_dial",
        label: "Dial configured test target",
        description: "Dial the single configured alias through its fixed TwiML outgoing application. Requires a ready local caller browser, provider time limit confirmation and bounded persisted call ownership. Takes no arbitrary number.",
        parameters: Type.Object({
            target: Type.String()
        }),
        async execute(_id, p, signal) {
            return emit(await caller.dial(p.target, signal));
        }
    });
    pi.registerTool({
        name: "caller_status",
        label: "Owned WebRTC call status",
        description: "Read local browser state for an owned call_id and persist terminal status. A connected browser call does not prove a human agent answered.",
        parameters: Type.Object({
            call_id: Type.String()
        }),
        async execute(_id, p) {
            return emit(await caller.status(p.call_id));
        }
    });
    pi.registerTool({
        name: "caller_speak",
        label: "Speak through WebRTC test caller",
        description: "Generate ElevenLabs speech and feed its local WAV into the owned browser caller microphone stream. No S3 or public media host is required.",
        parameters: Type.Object({
            call_id: Type.String(),
            text: Type.String({
                minLength: 1,
                maxLength: 2000
            })
        }),
        async execute(_id, p, signal) {
            return emit(await caller.speak(p.call_id, p.text, signal));
        }
    });
    pi.registerTool({
        name: "caller_play",
        label: "Play local WAV or MP3 into caller",
        description: "Feed a local WAV or MP3 within configured allowed_audio_directory into the owned caller microphone stream. Remote URLs and arbitrary filesystem paths are rejected.",
        parameters: Type.Object({
            call_id: Type.String(),
            path: Type.String()
        }),
        async execute(_id, p, signal) {
            return emit(await caller.play(p.call_id, p.path, signal));
        }
    });
    pi.registerTool({
        name: "caller_press_digits",
        label: "Send caller DTMF",
        description: "Send bounded DTMF through the owned connected WebRTC call.",
        parameters: Type.Object({
            call_id: Type.String(),
            digits: Type.String({
                pattern: "^[0-9*#w]{1,32}$"
            })
        }),
        async execute(_id, p, signal) {
            return emit(await caller.pressDigits(p.call_id, p.digits, signal));
        }
    });
    pi.registerTool({
        name: "caller_hangup",
        label: "Hang up owned WebRTC caller",
        description: "Disconnect only the local call owned by this call_id. Previous runtimes and unowned calls fail closed.",
        parameters: Type.Object({
            call_id: Type.String()
        }),
        async execute(_id, p, signal) {
            return emit(await caller.hangup(p.call_id, signal));
        }
    });
}
