import { randomUUID } from "node:crypto";
import { readFile, writeFile, mkdir, rename, open, unlink, realpath, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join, relative, extname, isAbsolute } from "node:path";
import { TtsEngine, parseApiKey } from "./tts/engine.ts";
import { CallerRuntime, type RuntimeOptions } from "./runtime.ts";
import { ctmTokenProvider } from "./ctm-token.ts";
export interface Config {
    credential_source?: "environment" | "ctm-dev";
    ctm_account_id?: number;
    account_sid: string;
    application_sid: string;
    identity: string;
    target_alias: string;
    target_number: string;
    provider_time_limit_confirmed?: boolean;
    apiKeySidEnv?: string;
    apiKeySecretEnv?: string;
    allowed_audio_directory?: string;
    maxCallsPerDay?: number;
    maxCallSeconds?: number;
}
export interface Snapshot {
    ready: boolean;
    call_status: string;
    call_sid?: string;
    heartbeat_at?: number;
    error?: string;
}
export interface Runtime {
    start(): Promise<{
        url: string;
    }>;
    readonly snapshot: Snapshot;
    command(action: "dial" | "hangup" | "digits" | "play" | "stop_audio", payload: Record<string, unknown>, signal?: AbortSignal): Promise<Record<string, unknown>>;
    registerAudio(path: string): Promise<string>;
    close(): Promise<void>;
}
interface Attempt {
    id: string;
    created_at: string;
    state: "pending" | "unknown" | "known" | "completed";
    account_sid: string;
    application_sid: string;
    target: string;
    target_number: string;
    sid?: string;
}
interface Registry {
    version: 1;
    attempts: Attempt[];
}
export interface Receipt {
    call_id: string;
    call_sid?: string;
    target: string;
    status: string;
    agent_connected: "unverified";
}
interface Options {
    synthesisDirectory?: string;
    tokenProviderFactory?: typeof ctmTokenProvider;
    registryDir?: string;
    config?: () => Promise<Config>;
    credential?: (name: string) => Promise<string | undefined>;
    runtimeFactory?: (options: RuntimeOptions) => Runtime;
    synthesize?: (text: string, signal?: AbortSignal) => Promise<string>;
    now?: () => Date;
}
const AC = /^AC[0-9a-fA-F]{32}$/;
const AP = /^AP[0-9a-fA-F]{32}$/;
const SK = /^SK[0-9a-fA-F]{32}$/;
const CA = /^CA[0-9a-fA-F]{32}$/;
const NUMBER = /^\+[1-9]\d{6,14}$/;
class CallerClosedError extends Error { constructor() { super("Caller session is closed"); } }
const finished = new Set(["disconnected", "failed", "completed", "canceled", "busy", "no-answer"]);
function validateConfig(c: Config): Config {
    if (c?.credential_source !== undefined && c.credential_source !== "environment" && c.credential_source !== "ctm-dev") throw new Error("credential_source must be environment or ctm-dev");
    if (c?.credential_source === "ctm-dev" && (!Number.isSafeInteger(c.ctm_account_id) || c.ctm_account_id! < 1)) throw new Error("ctm_account_id is required for ctm-dev credentials");
    if (!c || !AC.test(c.account_sid) || !AP.test(c.application_sid) || typeof c.identity !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(c.identity) || typeof c.target_alias !== "string" || !/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(c.target_alias) || !NUMBER.test(c.target_number))
        throw new Error("Invalid caller configuration; exact account, application, identity and one target alias/number are required");
    for (const name of [c.apiKeySidEnv, c.apiKeySecretEnv])
        if (name !== undefined && !/^[A-Z][A-Z0-9_]{0,79}$/.test(name))
            throw new Error("Invalid credential environment variable name");
    if (c.maxCallsPerDay !== undefined && (!Number.isInteger(c.maxCallsPerDay) || c.maxCallsPerDay < 1 || c.maxCallsPerDay > 6))
        throw new Error("maxCallsPerDay must be 1\u20136");
    if (c.maxCallSeconds !== undefined && (!Number.isInteger(c.maxCallSeconds) || c.maxCallSeconds < 1 || c.maxCallSeconds > 180))
        throw new Error("maxCallSeconds must be 1\u2013180");
    if (c.allowed_audio_directory !== undefined && (typeof c.allowed_audio_directory !== "string" || !isAbsolute(c.allowed_audio_directory)))
        throw new Error("allowed_audio_directory must be an absolute directory");
    return c;
}
async function loadConfig(): Promise<Config> {
    try {
        return validateConfig(JSON.parse(await readFile(join(homedir(), ".pi", "agent", "test-caller.json"), "utf8")));
    }
    catch {
        throw new Error("Create valid ~/.pi/agent/test-caller.json from config.example.json; do not add credential secrets to the JSON");
    }
}
async function credential(name: string): Promise<string | undefined> {
    if (process.env[name]?.trim())
        return process.env[name]!.trim();
    try {
        const contents = await readFile(join(homedir(), ".env"), "utf8");
        for (const line of contents.split(/\r?\n/)) {
            const m = line.match(/^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=\s*(.*)$/);
            if (m?.[1] === name)
                return parseApiKey(`ELEVENLABS_API_KEY=${m[2]}`);
        }
    }
    catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "ENOENT")
            throw new Error("Cannot read configured caller credentials from ~/.env");
    }
}
function validAttempt(value: unknown): value is Attempt {
    if (!value || typeof value !== "object")
        return false;
    const a = value as Attempt;
    return typeof a.id === "string" && /^[0-9a-f-]{36}$/.test(a.id) && typeof a.created_at === "string" && Number.isFinite(Date.parse(a.created_at)) && ["pending", "unknown", "known", "completed"].includes(a.state) && AC.test(a.account_sid) && AP.test(a.application_sid) && typeof a.target === "string" && NUMBER.test(a.target_number) && (a.sid === undefined || CA.test(a.sid));
}
export class CallerEngine {
    private options: Required<Options>;
    private runtime?: Runtime;
    private runtimeConfig?: string;
    private runtimeUrl?: string;
    private initializing?: Promise<Runtime>;
    private initializingConfig?: string;
    private activeId?: string;
    private tts: TtsEngine;
    private closed = false;
    constructor(options: Options = {}) {
        this.tts = new TtsEngine({ cacheDir: options.synthesisDirectory ?? join(homedir(), ".pi", "agent", "tts") });
        this.options = {
            synthesisDirectory: join(homedir(), ".pi", "agent", "tts"),
            registryDir: join(homedir(), ".pi", "agent", "test-caller"),
            config: loadConfig,
            credential,
            tokenProviderFactory: ctmTokenProvider,
            runtimeFactory: o => new CallerRuntime(o),
            synthesize: async (text, signal) => {
                const r = await this.tts.speak({
                    text,
                    destination: "file"
                }, signal);
                if (r.status !== "completed" || !r.audio_path)
                    throw new Error("ElevenLabs synthesis did not complete");
                return r.audio_path;
            },
            now: () => new Date(),
            ...options
        };
    }
    private async config(): Promise<Config> {
        if (this.closed) throw new CallerClosedError();
        const config = validateConfig(await this.options.config());
        if (this.closed) throw new CallerClosedError();
        return config;
    }
    private async getRuntime(c: Config): Promise<Runtime> {
        if (this.closed) throw new CallerClosedError();
        if (this.initializing) {
            if (this.initializingConfig !== JSON.stringify(c)) throw new Error("Caller configuration changed during runtime initialization");
            return this.initializing;
        }
        this.initializingConfig = JSON.stringify(c);
        this.initializing = this.initializeRuntime(c);
        try {
            return await this.initializing;
        }
        finally {
            this.initializing = undefined;
            this.initializingConfig = undefined;
        }
    }
    private async initializeRuntime(c: Config): Promise<Runtime> {
        if (this.closed) throw new CallerClosedError();
        const fingerprint = JSON.stringify(c);
        if (this.runtime) {
            if (this.runtimeConfig !== fingerprint)
                throw new Error("Caller configuration changed; restart the caller session before continuing");
            return this.runtime;
        }
        const runtimeOptions: RuntimeOptions = {
            accountSid: c.account_sid,
            applicationSid: c.application_sid,
            identity: c.identity,
            maxCallSeconds: c.maxCallSeconds ?? 180
        };
        if (c.credential_source === "ctm-dev") {
            runtimeOptions.tokenProvider = this.options.tokenProviderFactory(c.ctm_account_id!, c.account_sid, c.application_sid, c.identity);
        } else {
            const apiKeySid = await this.options.credential(c.apiKeySidEnv ?? "TEST_CALLER_TWILIO_API_KEY_SID");
            const apiSecret = await this.options.credential(c.apiKeySecretEnv ?? "TEST_CALLER_TWILIO_API_KEY_SECRET");
            if (!apiKeySid || !SK.test(apiKeySid) || !apiSecret) throw new Error("Configured Twilio API key SID/secret is missing or invalid");
            runtimeOptions.apiKeySid = apiKeySid;
            runtimeOptions.apiSecret = apiSecret;
        }
        if (this.closed) throw new CallerClosedError();
        const runtime = this.options.runtimeFactory(runtimeOptions);
        try {
            const started = await runtime.start();
            this.runtimeUrl = started.url;
        }
        catch {
            await runtime.close();
            throw new Error("Local caller runtime could not start");
        }
        if (this.closed) {
            await runtime.close();
            throw new CallerClosedError();
        }
        this.runtime = runtime;
        this.runtimeConfig = fingerprint;
        return runtime;
    }
    private async readRegistry(): Promise<Registry> {
        try {
            const r = JSON.parse(await readFile(join(this.options.registryDir, "registry.json"), "utf8")) as Registry;
            if (r.version !== 1 || !Array.isArray(r.attempts) || !r.attempts.every(validAttempt) || new Set(r.attempts.map(a => a.id)).size !== r.attempts.length)
                throw new Error("Invalid registry");
            return r;
        }
        catch (e) {
            if ((e as NodeJS.ErrnoException).code === "ENOENT")
                return {
                    version: 1,
                    attempts: []
                };
            throw new Error("Caller registry is corrupt or unreadable; reconcile manually");
        }
    }
    private async writeRegistry(r: Registry): Promise<void> {
        const temp = join(this.options.registryDir, `${randomUUID()}.tmp`);
        await writeFile(temp, JSON.stringify(r, null, 2), {
            mode: 384,
            flag: "wx"
        });
        try {
            await rename(temp, join(this.options.registryDir, "registry.json"));
        }
        catch {
            try {
                await unlink(temp);
            }
            catch {
                throw new Error("Caller registry write and cleanup failed");
            }
            throw new Error("Caller registry write failed");
        }
    }
    private async locked<T>(run: () => Promise<T>, signal?: AbortSignal): Promise<T> {
        if (signal?.aborted)
            throw new Error("Caller operation canceled");
        await mkdir(this.options.registryDir, {
            recursive: true,
            mode: 448
        });
        const path = join(this.options.registryDir, "registry.lock");
        let lock;
        try {
            lock = await open(path, "wx", 384);
            await lock.writeFile(JSON.stringify({
                pid: process.pid,
                created_at: this.options.now().toISOString()
            }));
        }
        catch {
            throw new Error("Caller registry lock exists or cannot be created; reconcile a stale lock manually");
        }
        try {
            return await run();
        }
        finally {
            await lock.close();
            await unlink(path);
        }
    }
    private owned(r: Registry, c: Config, id: string): Attempt {
        const a = r.attempts.find(a => a.id === id);
        if (!a)
            throw new Error("call_id is not owned by this caller registry");
        if (a.account_sid !== c.account_sid || a.application_sid !== c.application_sid || a.target !== c.target_alias || a.target_number !== c.target_number)
            throw new Error("Configured caller identity differs from the owned record");
        return a;
    }
    private snapshot(runtime: Runtime, a?: Attempt): Snapshot {
        const s = runtime.snapshot;
        if (a?.sid && s.call_sid && a.sid !== s.call_sid)
            throw new Error("Runtime call SID differs from the owned record");
        if (s.call_sid && !CA.test(s.call_sid))
            throw new Error("Invalid runtime call SID");
        return s;
    }
    private ready(s: Snapshot): void {
        if (!s.ready || !s.heartbeat_at || this.options.now().getTime() - s.heartbeat_at > 15000)
            throw new Error("Open the local caller page and start audio; a fresh browser heartbeat is required");
    }
    private receipt(a: Attempt, s?: Snapshot): Receipt {
        return {
            call_id: a.id,
            call_sid: a.sid,
            target: a.target,
            status: s?.call_status ?? a.state,
            agent_connected: "unverified"
        };
    }
    private async command(runtime: Runtime, action: Parameters<Runtime["command"]>[0], payload: Record<string, unknown>, signal?: AbortSignal): Promise<Record<string, unknown>> {
        try {
            return await runtime.command(action, payload, signal);
        }
        catch {
            throw new Error(signal?.aborted ? "Caller command canceled; call state may still require checking" : "Caller command failed or timed out; check caller_status before retrying");
        }
    }
    async setup(): Promise<unknown> {
        try {
            const c = await this.config();
            const r = await this.readRegistry();
            const runtime = await this.getRuntime(c);
            const s = this.snapshot(runtime);
            return {
                configured: true,
                credential_source: c.credential_source ?? "environment",
                ctm_account_id: c.credential_source === "ctm-dev" ? c.ctm_account_id : undefined,
                url: this.runtimeUrl,
                ready: s.ready,
                call_status: s.call_status,
                account_sid: c.account_sid,
                application_sid: c.application_sid,
                target: {
                    alias: c.target_alias,
                    number: c.target_number
                },
                provider_time_limit_confirmed: c.provider_time_limit_confirmed === true,
                limits: {
                    active: 1,
                    per_24_hours: c.maxCallsPerDay ?? 5,
                    max_call_seconds: c.maxCallSeconds ?? 180
                },
                owned: r.attempts.map(a => this.receipt(a)),
                note: "The local URL contains a session access secret. Open it locally and press Start audio. The caller uses generated input without physical microphone access. Provider call acceptance does not prove agent connection."
            };
        }
        catch (e) {
            return {
                configured: false,
                error: e instanceof Error ? e.message : "Caller setup unavailable"
            };
        }
    }
    async dial(target: string, signal?: AbortSignal): Promise<Receipt> {
        return this.locked(async () => {
            const c = await this.config();
            if (target !== c.target_alias)
                throw new Error("Target must be the exact configured alias; dial takes no telephone number");
            if (c.provider_time_limit_confirmed !== true)
                throw new Error("Confirm the fixed TwiML application route uses provider <Dial timeLimit> before dialing");
            const r = await this.readRegistry();
            if (r.attempts.some(a => a.state !== "completed"))
                throw new Error("Active, pending or unknown call exists; check caller_status or reconcile manually before dialing");
            const now = this.options.now();
            if (r.attempts.filter(a => Date.parse(a.created_at) >= now.getTime() - 86400000).length >= (c.maxCallsPerDay ?? 5))
                throw new Error("Caller attempt cap reached for the last 24 hours");
            const runtime = await this.getRuntime(c);
            this.ready(this.snapshot(runtime));
            if (signal?.aborted)
                throw new Error("Caller operation canceled");
            const a: Attempt = {
                id: randomUUID(),
                created_at: now.toISOString(),
                state: "pending",
                account_sid: c.account_sid,
                application_sid: c.application_sid,
                target: c.target_alias,
                target_number: c.target_number
            };
            r.attempts.push(a);
            await this.writeRegistry(r);
            this.activeId = a.id;
            try {
                await this.command(runtime, "dial", {}, signal);
                const s = this.snapshot(runtime);
                a.sid = s.call_sid;
                a.state = finished.has(s.call_status) ? "completed" : "known";
                await this.writeRegistry(r);
                return this.receipt(a, s);
            }
            catch {
                a.state = "unknown";
                await this.writeRegistry(r);
                throw new Error(`Dial outcome unknown (call_id ${a.id}); do not retry. Check caller_status or reconcile manually`);
            }
        }, signal);
    }
    async status(id: string): Promise<Receipt> {
        return this.locked(async () => {
            const c = await this.config();
            const r = await this.readRegistry();
            const a = this.owned(r, c, id);
            if (a.state === "completed")
                return this.receipt(a);
            if (this.activeId !== id || !this.runtime)
                throw new Error("Owned call belongs to a previous runtime; reconcile manually before more calls");
            const s = this.snapshot(this.runtime, a);
            if (s.call_sid)
                a.sid = s.call_sid;
            if (finished.has(s.call_status))
                a.state = "completed";
            await this.writeRegistry(r);
            return this.receipt(a, s);
        });
    }
    private ensureConnected(runtime: Runtime, a: Attempt): Snapshot {
        if (this.activeId !== a.id)
            throw new Error("Owned call changed before audio playback");
        const s = this.snapshot(runtime, a);
        this.ready(s);
        if (s.call_status !== "connected")
            throw new Error("Audio and DTMF require a connected local WebRTC call");
        return s;
    }
    private async active<T>(id: string, run: (runtime: Runtime, c: Config, a: Attempt) => Promise<T>, signal?: AbortSignal): Promise<T> {
        const context = await this.locked(async () => {
            const c = await this.config();
            const r = await this.readRegistry();
            const a = this.owned(r, c, id);
            if (a.state === "completed" || this.activeId !== id || !this.runtime)
                throw new Error("Owned call is not active in this runtime");
            const s = this.ensureConnected(this.runtime, a);
            if (!a.sid && s.call_sid) {
                a.sid = s.call_sid;
                await this.writeRegistry(r);
            }
            return {
                runtime: this.runtime,
                c,
                a
            };
        }, signal);
        if (signal?.aborted)
            throw new Error("Caller operation canceled");
        return run(context.runtime, context.c, context.a);
    }
    private playbackReceipt(a: Attempt, runtime: Runtime, result: Record<string, unknown>): Receipt & {
        playback_status: string;
        duration_ms?: number;
        call_received: "unverified";
    } {
        return {
            ...this.receipt(a, this.snapshot(runtime, a)),
            playback_status: typeof result.status === "string" ? result.status : "unverified",
            duration_ms: typeof result.duration_ms === "number" ? result.duration_ms : undefined,
            call_received: "unverified"
        };
    }
    private async audioPath(path: string, c: Config): Promise<string> {
        const resolved = await realpath(path);
        const roots = new Set([this.options.synthesisDirectory, c.allowed_audio_directory ?? this.options.synthesisDirectory]);
        let allowed = false;
        for (const root of roots) {
            let directory: string;
            try { directory = await realpath(root); }
            catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") continue; throw error; }
            const rel = relative(directory, resolved);
            if (rel && !rel.startsWith("..") && !isAbsolute(rel)) allowed = true;
        }
        if (!allowed || ![".wav", ".mp3"].includes(extname(resolved).toLowerCase())) throw new Error("Audio path must be a WAV or MP3 inside allowed_audio_directory or the TTS cache");
        const info = await stat(resolved);
        if (!info.isFile() || info.size < 4 || info.size > 10 * 1024 * 1024)
            throw new Error("Audio file must be nonempty and at most 10 MiB");
        return resolved;
    }
    async play(id: string, path: string, signal?: AbortSignal): Promise<Receipt> {
        return this.active(id, async (runtime, c, a) => {
            const audio = await this.audioPath(path, c);
            this.ensureConnected(runtime, a);
            const audioId = await runtime.registerAudio(audio);
            this.ensureConnected(runtime, a);
            const result = await this.command(runtime, "play", {
                audio_id: audioId
            }, signal);
            return this.playbackReceipt(a, runtime, result);
        }, signal);
    }
    async speak(id: string, text: string, signal?: AbortSignal): Promise<Receipt> {
        if (typeof text !== "string" || !text.trim() || text.length > 2000)
            throw new Error("Speech text must contain 1\u20132000 characters");
        return this.active(id, async (runtime, c, a) => {
            let path: string;
            try {
                path = await this.options.synthesize(text, signal);
            }
            catch {
                throw new Error("ElevenLabs synthesis failed or was canceled");
            }
            const audio = await this.audioPath(path, c);
            this.ensureConnected(runtime, a);
            const audioId = await runtime.registerAudio(audio);
            this.ensureConnected(runtime, a);
            const result = await this.command(runtime, "play", {
                audio_id: audioId
            }, signal);
            return this.playbackReceipt(a, runtime, result);
        }, signal);
    }
    async pressDigits(id: string, digits: string, signal?: AbortSignal): Promise<Receipt> {
        if (!/^[0-9*#w]{1,32}$/.test(digits))
            throw new Error("DTMF must contain 1\u201332 digits, *, # or lowercase w");
        return this.active(id, async (runtime, _c, a) => {
            await this.command(runtime, "digits", {
                digits
            }, signal);
            return this.receipt(a, this.snapshot(runtime, a));
        }, signal);
    }
    async hangup(id: string, signal?: AbortSignal): Promise<Receipt> {
        return this.locked(async () => {
            const c = await this.config();
            const r = await this.readRegistry();
            const a = this.owned(r, c, id);
            if (a.state === "completed")
                return this.receipt(a);
            if (this.activeId !== id || !this.runtime)
                throw new Error("Owned call belongs to a previous runtime; reconcile manually");
            this.ready(this.snapshot(this.runtime, a));
            await this.command(this.runtime, "hangup", {}, signal);
            const s = this.snapshot(this.runtime, a);
            if (finished.has(s.call_status))
                a.state = "completed";
            await this.writeRegistry(r);
            return this.receipt(a, s);
        }, signal);
    }
    async close(): Promise<void> {
        this.closed = true;
        this.tts.shutdown();
        const initializing = this.initializing;
        if (initializing) {
            try { await initializing; }
            catch (error) { if (!(error instanceof CallerClosedError)) throw new Error("Caller runtime initialization failed during shutdown"); }
        }
        const runtime = this.runtime;
        this.runtime = undefined;
        await runtime?.close();
    }
}
