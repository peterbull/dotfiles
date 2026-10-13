import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, readFile, symlink, mkdir, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CallerEngine, type Config, type Runtime, type Snapshot } from "./engine.ts";
const config: Config = {
    account_sid: "AC" + "a".repeat(32),
    application_sid: "AP" + "b".repeat(32),
    identity: "test-caller",
    target_alias: "desk",
    target_number: "+15550000002",
    provider_time_limit_confirmed: true
};
const sid = "CA" + "c".repeat(32);
async function setup(extra: Record<string, unknown> = {}) {
    const registryDir = await mkdtemp(join(tmpdir(), "caller-test-"));
    const audioDir = join(registryDir, "audio");
    await mkdir(audioDir);
    const audioPath = join(audioDir, "speech.wav");
    await writeFile(audioPath, Buffer.alloc(48));
    const commands: {
        action: string;
        payload: Record<string, unknown>;
    }[] = [];
    const audio: string[] = [];
    let snapshot: Snapshot = {
        ready: true,
        call_status: "idle",
        heartbeat_at: Date.now()
    };
    const runtime: Runtime = {
        start: async () => ({
            url: "http://127.0.0.1:1234/#session-secret"
        }),
        get snapshot() {
            return snapshot;
        },
        command: async (action, payload) => {
            commands.push({
                action,
                payload
            });
            if (action === "dial")
                snapshot = {
                    ...snapshot,
                    call_status: "connected",
                    call_sid: sid
                };
            if (action === "hangup")
                snapshot = {
                    ...snapshot,
                    call_status: "disconnected"
                };
            return {};
        },
        registerAudio: async (path) => {
            audio.push(path);
            return "opaque-audio-id";
        },
        close: async () => {
        }
    };
    const options = {
        registryDir,
        config: async () => ({
            ...config,
            allowed_audio_directory: audioDir
        }),
        credential: async (name: string) => name.endsWith("_SID") ? "SK" + "d".repeat(32) : "secret-value",
        runtimeFactory: () => runtime,
        synthesize: async () => audioPath,
        ...extra
    };
    return {
        engine: new CallerEngine(options),
        registryDir,
        commands,
        audio,
        audioDir,
        audioPath,
        runtime,
        options,
        setSnapshot: (value: Partial<Snapshot>) => {
            snapshot = {
                ...snapshot,
                ...value
            };
        }
    };
}
test("setup is redacted and starts only local runtime", async () => {
    const s = await setup();
    const result = await s.engine.setup();
    assert.equal((result as any).ready, true);
    assert.ok(JSON.stringify(result).includes("#session-secret"));
    assert.ok(!JSON.stringify(result).includes("secret-value"));
    assert.equal(s.commands.length, 0);
});
test("dial only configured alias, no arbitrary To, persisted ownership and active cap", async () => {
    const s = await setup();
    await assert.rejects(s.engine.dial("+15550000003"), /alias/);
    const r = await s.engine.dial("desk");
    assert.equal(r.call_sid, sid);
    assert.equal(r.agent_connected, "unverified");
    assert.deepEqual(s.commands, [{
            action: "dial",
            payload: {}
        }]);
    const stored = JSON.parse(await readFile(join(s.registryDir, "registry.json"), "utf8"));
    assert.equal(stored.attempts[0].state, "known");
    await assert.rejects(s.engine.dial("desk"), /Active/);
});
test("provider cap confirmation, missing credentials and stale browser fail before dial", async () => {
    for (const extra of [{
            config: async () => ({
                ...config,
                provider_time_limit_confirmed: false
            })
        }, {
            credential: async () => undefined
        }]) {
        const s = await setup(extra);
        await assert.rejects(s.engine.dial("desk"));
        assert.equal(s.commands.length, 0);
    }
    const s = await setup();
    s.setSnapshot({
        heartbeat_at: 1
    });
    await assert.rejects(s.engine.dial("desk"), /heartbeat/);
});
test("unknown dispatch blocks restart and creation is never retried", async () => {
    const s = await setup();
    s.runtime.command = async () => {
        throw new Error("secret-value");
    };
    await assert.rejects(s.engine.dial("desk"), /unknown/);
    const restarted = new CallerEngine(s.options);
    await assert.rejects(restarted.dial("desk"), /unknown/);
    const records = JSON.parse(await readFile(join(s.registryDir, "registry.json"), "utf8"));
    assert.equal(records.attempts.length, 1);
    assert.equal(records.attempts[0].state, "unknown");
});
test("unknown dispatch can reconcile only observed terminal state in same runtime", async () => {
    const s = await setup();
    s.runtime.command = async () => {
        throw new Error("timeout");
    };
    await assert.rejects(s.engine.dial("desk"));
    const records = JSON.parse(await readFile(join(s.registryDir, "registry.json"), "utf8"));
    const id = records.attempts[0].id;
    s.setSnapshot({
        call_status: "idle"
    });
    await s.engine.status(id);
    assert.equal(JSON.parse(await readFile(join(s.registryDir, "registry.json"), "utf8")).attempts[0].state, "unknown");
    s.setSnapshot({
        call_status: "failed"
    });
    await s.engine.status(id);
    assert.equal(JSON.parse(await readFile(join(s.registryDir, "registry.json"), "utf8")).attempts[0].state, "completed");
});
test("owned runtime and exact SID required for audio and hangup", async () => {
    const s = await setup();
    const r = await s.engine.dial("desk");
    await assert.rejects(s.engine.hangup("unknown"), /owned/);
    s.setSnapshot({
        call_sid: "CA" + "e".repeat(32)
    });
    await assert.rejects(s.engine.hangup(r.call_id), /SID/);
    const restarted = new CallerEngine(s.options);
    await assert.rejects(restarted.hangup(r.call_id), /previous runtime/);
});
test("local audio and TTS are registered with opaque ids, digits are validated, hangup owned", async () => {
    const s = await setup();
    const r = await s.engine.dial("desk");
    await s.engine.play(r.call_id, s.audioPath);
    await s.engine.speak(r.call_id, "Hello");
    assert.deepEqual(s.audio, [await realpath(s.audioPath), await realpath(s.audioPath)]);
    assert.deepEqual(s.commands.at(-1), {
        action: "play",
        payload: {
            audio_id: "opaque-audio-id"
        }
    });
    await s.engine.pressDigits(r.call_id, "12#w");
    await assert.rejects(s.engine.pressDigits(r.call_id, "<x>"));
    await s.engine.hangup(r.call_id);
    assert.equal((await s.engine.status(r.call_id)).status, "completed");
});
test("audio realpath fence rejects URL, outside file and symlink escape", async () => {
    const s = await setup();
    const r = await s.engine.dial("desk");
    const outside = join(s.registryDir, "outside.wav");
    await writeFile(outside, Buffer.alloc(48));
    const link = join(s.audioDir, "escape.wav");
    await symlink(outside, link);
    for (const path of [outside, link, "https://example.com/speech.wav"])
        await assert.rejects(s.engine.play(r.call_id, path));
    assert.equal(s.audio.length, 0);
});
test("daily cap and corrupted registry fail closed; process lock prevents races", async () => {
    const s = await setup({
        config: async () => ({
            ...config,
            maxCallsPerDay: 1
        })
    });
    const r = await s.engine.dial("desk");
    await s.engine.hangup(r.call_id);
    await assert.rejects(s.engine.dial("desk"), /24 hours/);
    const b = await setup();
    await writeFile(join(b.registryDir, "registry.json"), "bad");
    await assert.rejects(b.engine.dial("desk"), /registry/);
    const c = await setup();
    await writeFile(join(c.registryDir, "registry.lock"), "stale");
    await assert.rejects(c.engine.dial("desk"), /lock/);
});
test("concurrent engine sessions cannot both dial", async () => {
    const s = await setup();
    const other = new CallerEngine(s.options);
    const results = await Promise.allSettled([s.engine.dial("desk"), other.dial("desk")]);
    assert.equal(results.filter(r => r.status === "fulfilled").length, 1);
    assert.equal(s.commands.filter(c => c.action === "dial").length, 1);
});
test("cancellation before dispatch avoids a call; synthesis errors redact provider details", async () => {
    const s = await setup({
        synthesize: async () => {
            throw new Error("secret-value");
        }
    });
    const ctrl = new AbortController();
    ctrl.abort();
    await assert.rejects(s.engine.dial("desk", ctrl.signal), /canceled/);
    assert.equal(s.commands.length, 0);
    const r = await s.engine.dial("desk");
    await assert.rejects(s.engine.speak(r.call_id, "x"), e => !String(e).includes("secret-value"));
});
test("hangup interrupts ownership during slow synthesis without waiting on registry lock", async () => {
    let release!: () => void;
    const s = await setup({
        synthesize: async () => {
            await new Promise<void>(r => release = r);
            return "/unavailable.wav";
        }
    });
    const r = await s.engine.dial("desk");
    const speech = s.engine.speak(r.call_id, "hello");
    while (!release)
        await new Promise(r => setImmediate(r));
    await s.engine.hangup(r.call_id);
    release();
    await assert.rejects(speech);
    assert.equal(s.commands.filter(c => c.action === "play").length, 0);
});
test("playback receipts preserve stopped versus completed and unverified reception", async () => {
    const s = await setup();
    const r = await s.engine.dial("desk");
    s.runtime.command = async () => ({
        status: "stopped",
        duration_ms: 1000
    });
    const result = await s.engine.play(r.call_id, s.audioPath) as any;
    assert.equal(result.playback_status, "stopped");
    assert.equal(result.duration_ms, 1000);
    assert.equal(result.call_received, "unverified");
});
test("uppercase W is rejected by the SDK-compatible DTMF schema", async () => {
    const s = await setup();
    const r = await s.engine.dial("desk");
    await assert.rejects(s.engine.pressDigits(r.call_id, "W"));
});
test('explicit CTM source uses account-scoped signer without environment credential lookup',async()=>{
 let signedConfig:unknown[]=[];let options:any;
 const s=await setup({config:async()=>({...config,credential_source:'ctm-dev',ctm_account_id:1}),credential:async()=>{throw new Error('environment must not be read')},tokenProviderFactory:(...args:unknown[])=>{signedConfig=args;return async()=> 'internal-token'},runtimeFactory:(o:unknown)=>{options=o;return s.runtime}});
 const result=await s.engine.setup() as any;assert.equal(result.configured,true);assert.equal(result.credential_source,'ctm-dev');assert.deepEqual(signedConfig,[1,config.account_sid,config.application_sid,config.identity]);assert.equal(options.apiKeySid,undefined);assert.equal(options.apiSecret,undefined);assert.equal(await options.tokenProvider(),'internal-token');assert.ok(!JSON.stringify(result).includes('internal-token'));
});
test('CTM source requires a positive exact account ID and rejects unknown credential sources',async()=>{for(const value of [undefined,0,-1,1.5,'1']){const s=await setup({config:async()=>({...config,credential_source:'ctm-dev',ctm_account_id:value})});await assert.rejects(s.engine.dial('desk'),/ctm_account_id/);}const s=await setup({config:async()=>({...config,credential_source:'implicit-master'})});await assert.rejects(s.engine.dial('desk'),/credential_source/);});
test('shutdown during delayed runtime startup closes the late server and cannot resurrect',async()=>{
 const s=await setup();let release!:()=>void;let closes=0;
 s.runtime.start=async()=>new Promise(r=>{release=()=>r({url:'http://127.0.0.1:1234/#secret'})});s.runtime.close=async()=>{closes++};
 const starting=s.engine.setup();while(!release)await new Promise(r=>setImmediate(r));const closing=s.engine.close();release();
 const result=await starting as any;await closing;assert.equal(result.configured,false);assert.match(result.error,/closed/);assert.equal(closes,1);
 assert.equal((await s.engine.setup() as any).configured,false);await assert.rejects(s.engine.dial('desk'),/closed/);assert.equal(closes,1);
});
test('custom audio library preserves the separate owned synthesis cache root',async()=>{
 const s=await setup();const cache=join(s.registryDir,'tts-cache');await mkdir(cache);const generated=join(cache,'generated.wav');await writeFile(generated,Buffer.alloc(48));
 const engine=new CallerEngine({...s.options,synthesisDirectory:cache,synthesize:async()=>generated});const r=await engine.dial('desk');await engine.speak(r.call_id,'hello');assert.equal(s.audio[0],await realpath(generated));await engine.play(r.call_id,s.audioPath);assert.equal(s.audio[1],await realpath(s.audioPath));
});
test('audio larger than 10 MiB is rejected before browser registration',async()=>{const s=await setup();await writeFile(s.audioPath,Buffer.alloc(10*1024*1024+1));const r=await s.engine.dial('desk');await assert.rejects(s.engine.play(r.call_id,s.audioPath),/10 MiB/);assert.equal(s.audio.length,0);});
test('configured attempt cap accepts six while rejecting seven and keeps the default at five',async()=>{
 const six=await setup({config:async()=>({...config,maxCallsPerDay:6})});const result=await six.engine.setup() as any;assert.equal(result.configured,true);assert.equal(result.limits.per_24_hours,6);
 const seven=await setup({config:async()=>({...config,maxCallsPerDay:7})});await assert.rejects(seven.engine.dial('desk'),/1–6/);
 const defaults=await setup();assert.equal((await defaults.engine.setup() as any).limits.per_24_hours,5);
});
