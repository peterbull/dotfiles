import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile, rename, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
export const MODELS = ["eleven_multilingual_v2", "eleven_flash_v2_5", "eleven_turbo_v2_5"] as const;
export type Model = typeof MODELS[number];
export type Destination = "file" | "ctm-softphone";
export type Status = "generating" | "playing" | "completed" | "failed" | "stopped";
export interface SpeakInput {
    text: string;
    voice_id?: string;
    model?: Model;
    destination?: Destination;
    output_device?: string;
    wait?: boolean;
}
export interface Device {
    uid: string;
    name: string;
}
export interface Receipt {
    playback_id: string;
    status: Status;
    destination: Destination;
    output_device?: string;
    output_device_uid?: string;
    audio_path?: string;
    duration_ms?: number;
    cached: boolean;
    call_received: "unverified";
    error?: string;
}
interface Job {
    receipt: Receipt;
    controller: AbortController;
    finished: Promise<void>;
    settled: boolean;
}
interface Options {
    cacheDir?: string;
    readKey?: () => Promise<string | undefined>;
    fetch?: typeof fetch;
    devices?: (signal?: AbortSignal) => Promise<Device[]>;
    play?: (path: string, device: Device, signal: AbortSignal) => Promise<void>;
    timeoutMs?: number;
}
const MAX_PCM = 24000 * 2 * 120;
const terminal = (s: Status) => s === "completed" || s === "failed" || s === "stopped";
export function parseApiKey(contents: string): string | undefined {
    for (const line of contents.split(/\r?\n/)) {
        const match = line.match(/^\s*(?:export\s+)?ELEVENLABS_API_KEY\s*=\s*(.*)$/);
        if (!match)
            continue;
        const value = match[1].trim();
        if (value.startsWith("\"") || value.startsWith("'")) {
            const quote = value[0];
            const end = value.indexOf(quote, 1);
            if (end < 0)
                throw new Error("Malformed ELEVENLABS_API_KEY in ~/.env");
            return value.slice(1, end) || undefined;
        }
        return value.replace(/\s+#.*$/, "").trim() || undefined;
    }
}
async function readKey(): Promise<string | undefined> {
    if (process.env.ELEVENLABS_API_KEY?.trim())
        return process.env.ELEVENLABS_API_KEY.trim();
    try {
        return parseApiKey(await readFile(join(homedir(), ".env"), "utf8"));
    }
    catch (e) {
        if ((e as NodeJS.ErrnoException).code === "ENOENT")
            return undefined;
        throw new Error("Cannot read ELEVENLABS_API_KEY from ~/.env");
    }
}
export function pcmToWav(pcm: Buffer): Buffer {
    if (!pcm.length || pcm.length % 2 || pcm.length > MAX_PCM)
        throw new Error("Invalid PCM audio: must be nonempty 16-bit audio of at most 120 seconds");
    const h = Buffer.alloc(44);
    h.write("RIFF");
    h.writeUInt32LE(pcm.length + 36, 4);
    h.write("WAVEfmt ", 8);
    h.writeUInt32LE(16, 16);
    h.writeUInt16LE(1, 20);
    h.writeUInt16LE(1, 22);
    h.writeUInt32LE(24000, 24);
    h.writeUInt32LE(48000, 28);
    h.writeUInt16LE(2, 32);
    h.writeUInt16LE(16, 34);
    h.write("data", 36);
    h.writeUInt32LE(pcm.length, 40);
    return Buffer.concat([h, pcm]);
}
function validWav(wav: Buffer): boolean {
    return wav.length > 44 && wav.length <= MAX_PCM + 44 && wav.toString("ascii", 0, 4) === "RIFF" && wav.toString("ascii", 8, 16) === "WAVEfmt " && wav.readUInt32LE(4) === wav.length - 8 && wav.readUInt32LE(16) === 16 && wav.readUInt16LE(20) === 1 && wav.readUInt16LE(22) === 1 && wav.readUInt32LE(24) === 24000 && wav.readUInt32LE(28) === 48000 && wav.readUInt16LE(32) === 2 && wav.readUInt16LE(34) === 16 && wav.toString("ascii", 36, 40) === "data" && wav.readUInt32LE(40) === wav.length - 44 && (wav.length - 44) % 2 === 0;
}
export function parseDevices(output: string): Device[] {
    const devices: unknown = JSON.parse(output);
    if (!Array.isArray(devices) || !devices.every(d => d && typeof d.uid === "string" && d.uid.length > 0 && typeof d.name === "string" && d.name.length > 0)) {
        throw new Error("Native audio helper returned invalid devices");
    }
    return devices;
}
function runNative(args: string[], signal?: AbortSignal, timeoutMs = 150000): Promise<string> {
    return new Promise((resolve, reject) => {
        if (signal?.aborted) { reject(new Error("Playback stopped")); return; }
        const helper = fileURLToPath(new URL("./audio.swift", import.meta.url));
        const child = spawn("swift", [helper, ...args], { stdio: ["ignore", "pipe", "pipe"] });
        let output = "";
        let stderr = "";
        let settled = false;
        let timedOut = false;
        let killTimer: ReturnType<typeof setTimeout> | undefined;
        const stop = () => {
            if (killTimer || settled) return;
            child.kill("SIGTERM");
            killTimer = setTimeout(() => child.kill("SIGKILL"), 1000);
        };
        const timer = setTimeout(() => { timedOut = true; stop(); }, timeoutMs);
        signal?.addEventListener("abort", stop, { once: true });
        child.stdout.on("data", (chunk: Buffer) => { output = (output + chunk.toString()).slice(-65536); });
        child.stderr.on("data", (chunk: Buffer) => { stderr = (stderr + chunk.toString()).slice(-1000); });
        const finish = (error?: Error) => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            if (killTimer) clearTimeout(killTimer);
            signal?.removeEventListener("abort", stop);
            if (error) reject(error); else resolve(output);
        };
        child.once("error", () => finish(new Error("Cannot start Swift; macOS Swift toolchain is required for device playback")));
        child.once("close", code => finish(signal?.aborted ? new Error("Playback stopped") : timedOut ? new Error("Native audio operation timed out") : code === 0 ? undefined : new Error(`Native audio operation failed (exit ${code ?? "unknown"}): ${stderr.trim().slice(0, 400)}`)));
    });
}
export async function enumerateDevices(signal?: AbortSignal): Promise<Device[]> {
    return parseDevices(await runNative(["devices"], signal, 30000));
}
async function play(path: string, device: Device, signal: AbortSignal): Promise<void> {
    await runNative(["play", path, device.uid], signal);
}
export class TtsEngine {
    private options: Required<Options>;
    private jobs = new Map<string, Job>();
    private closed = false;
    constructor(options: Options = {}) {
        this.options = {
            cacheDir: join(homedir(), ".pi", "agent", "tts"),
            readKey,
            fetch: globalThis.fetch,
            devices: enumerateDevices,
            play,
            timeoutMs: 30000,
            ...options
        };
    }
    async devices(signal?: AbortSignal): Promise<Device[]> {
        return this.options.devices(signal);
    }
    status(id: string): Receipt {
        const j = this.jobs.get(id);
        if (!j)
            throw new Error("Unknown playback_id in this session");
        return {
            ...j.receipt
        };
    }
    async wait(id: string): Promise<Receipt> {
        const j = this.jobs.get(id);
        if (!j)
            throw new Error("Unknown playback_id in this session");
        await j.finished;
        return { ...j.receipt };
    }
    stop(id: string): Receipt {
        const j = this.jobs.get(id);
        if (!j)
            throw new Error("Unknown playback_id in this session");
        if (!terminal(j.receipt.status)) {
            j.receipt.status = "stopped";
            j.controller.abort();
        }
        return this.status(id);
    }
    shutdown(): void {
        this.closed = true;
        for (const id of this.jobs.keys())
            this.stop(id);
    }
    async speak(input: SpeakInput, signal?: AbortSignal): Promise<Receipt> {
        if (this.closed)
            throw new Error("TTS engine is shut down");
        if (typeof input.text !== "string" || !input.text.trim() || input.text.length > 2000)
            throw new Error("text must contain 1\u20132000 characters");
        const voice = input.voice_id ?? "JBFqnCBsd6RMkjVDRZzb";
        const model = input.model ?? "eleven_multilingual_v2";
        const destination = input.destination ?? "file";
        if (!/^[A-Za-z0-9_-]{1,80}$/.test(voice))
            throw new Error("Invalid voice_id");
        if (!MODELS.includes(model))
            throw new Error("Unsupported model");
        if (destination !== "file" && destination !== "ctm-softphone")
            throw new Error("Invalid destination");
        if (destination === "ctm-softphone" && (typeof input.output_device !== "string" || !input.output_device.trim()))
            throw new Error("ctm-softphone requires an exact output_device name");
        if (destination === "ctm-softphone" && [...this.jobs.values()].some(j => j.receipt.destination === destination && !j.settled))
            throw new Error("Softphone playback is already active");
        for (const [id, j] of this.jobs) {
            if (this.jobs.size < 100)
                break;
            if (j.settled)
                this.jobs.delete(id);
        }
        if (this.jobs.size >= 100)
            throw new Error("Too many active TTS jobs");
        const controller = new AbortController();
        const id = randomUUID();
        const job: Job = {
            receipt: {
                playback_id: id,
                status: "generating",
                destination,
                output_device: input.output_device,
                cached: false,
                call_received: "unverified"
            },
            controller,
            finished: Promise.resolve(),
            settled: false
        };
        this.jobs.set(id, job);
        const abort = () => this.stop(id);
        signal?.addEventListener("abort", abort, {
            once: true
        });
        if (signal?.aborted)
            abort();
        job.finished = this.generate(job, input.text, voice, model).finally(() => {
            job.settled = true;
            signal?.removeEventListener("abort", abort);
        });
        return input.wait === false ? this.status(id) : this.wait(id);
    }
    private async generate(job: Job, text: string, voice: string, model: Model): Promise<void> {
        let key: string | undefined;
        const signal = job.controller.signal;
        const check = () => {
            if (signal.aborted)
                throw new Error("Stopped");
        };
        try {
            check();
            if (job.receipt.destination === "ctm-softphone") {
                const devices = await this.options.devices(signal);
                check();
                const matches = devices.filter(d => d.name === job.receipt.output_device);
                if (matches.length !== 1) throw new Error("output_device must match exactly one available device; no speaker fallback");
                job.receipt.output_device_uid = matches[0].uid;
            }
            const cacheKey = createHash("sha256").update(JSON.stringify({
                text,
                voice,
                model,
                format: "pcm_24000",
                version: 1
            })).digest("hex");
            const path = join(this.options.cacheDir, `${cacheKey}.wav`);
            await mkdir(this.options.cacheDir, {
                recursive: true,
                mode: 448
            });
            check();
            let wav: Buffer | undefined;
            try {
                wav = await readFile(path);
                if (!validWav(wav))
                    throw new Error("Cached WAV is invalid; use a new cache directory");
                job.receipt.cached = true;
            }
            catch (e) {
                if ((e as NodeJS.ErrnoException).code !== "ENOENT")
                    throw e;
            }
            if (!wav) {
                key = await this.options.readKey();
                check();
                if (!key)
                    throw new Error("ELEVENLABS_API_KEY not found in process environment or ~/.env");
                const timeout = AbortSignal.timeout(this.options.timeoutMs);
                const requestSignal = AbortSignal.any([signal, timeout]);
                let pcm: Buffer;
                try {
                    const response = await this.options.fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=pcm_24000`, {
                        method: "POST",
                        headers: {
                            "xi-api-key": key,
                            "Content-Type": "application/json",
                            Accept: "application/octet-stream"
                        },
                        body: JSON.stringify({
                            text,
                            model_id: model
                        }),
                        signal: requestSignal,
                        redirect: "error"
                    });
                    check();
                    if (!response.ok) {
                        await response.body?.cancel();
                        throw new Error(`ElevenLabs speech request failed (HTTP ${response.status})`);
                    }
                    const contentType = response.headers.get("content-type")?.split(";")[0].trim();
                    if (contentType && !["application/octet-stream", "audio/pcm", "audio/x-pcm"].includes(contentType)) {
                        await response.body?.cancel();
                        throw new Error("ElevenLabs returned an unexpected audio content type");
                    }
                    if (!response.body)
                        throw new Error("ElevenLabs returned no audio");
                    const reader = response.body.getReader();
                    const chunks: Buffer[] = [];
                    let size = 0;
                    try {
                        while (true) {
                            check();
                            const r = await reader.read();
                            if (r.done)
                                break;
                            size += r.value.byteLength;
                            if (size > MAX_PCM)
                                throw new Error("ElevenLabs audio exceeds 120 seconds");
                            chunks.push(Buffer.from(r.value));
                        }
                    }
                    catch (e) {
                        await reader.cancel();
                        throw e;
                    }
                    finally {
                        reader.releaseLock();
                    }
                    pcm = Buffer.concat(chunks);
                }
                catch (e) {
                    if (timeout.aborted && !signal.aborted)
                        throw new Error("ElevenLabs synthesis timed out");
                    throw e;
                }
                check();
                wav = pcmToWav(pcm);
                const temp = join(this.options.cacheDir, `${cacheKey}.${job.receipt.playback_id}.tmp`);
                await writeFile(temp, wav, {
                    mode: 384,
                    flag: "wx"
                });
                try {
                    check();
                    await rename(temp, path);
                }
                catch (e) {
                    try {
                        await unlink(temp);
                    }
                    catch (cleanupError) {
                        throw new Error(`TTS cache cleanup failed: ${(cleanupError as NodeJS.ErrnoException).code ?? "unknown"}`);
                    }
                    throw e;
                }
            }
            check();
            job.receipt.audio_path = path;
            job.receipt.duration_ms = (wav.length - 44) / 48;
            if (job.receipt.destination === "ctm-softphone") {
                const devices = await this.options.devices(signal);
                check();
                const matches = devices.filter(d => d.uid === job.receipt.output_device_uid);
                if (matches.length !== 1)
                    throw new Error("output_device must match exactly one available device; no speaker fallback");
                const device = matches[0];
                if (!device.uid) throw new Error("Invalid audio device UID");
                job.receipt.status = "playing";
                await this.options.play(path, device, signal);
                check();
            }
            job.receipt.status = "completed";
        }
        catch (e) {
            if (signal.aborted || job.receipt.status === "stopped") {
                job.receipt.status = "stopped";
                return;
            }
            job.receipt.status = "failed";
            const message = e instanceof Error ? e.message : "TTS operation failed";
            job.receipt.error = (key ? message.split(key).join("[redacted]") : message).slice(0, 400);
        }
    }
}
