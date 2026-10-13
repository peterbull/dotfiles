import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TtsEngine, pcmToWav, parseDevices, parseApiKey } from "./engine.ts";
const pcm = Buffer.alloc(4800);
async function setup(extra = {}) {
    const cacheDir = await mkdtemp(join(tmpdir(), "tts-test-"));
    let calls = 0;
    const engine = new TtsEngine({
        cacheDir,
        readKey: async () => "secret-value",
        fetch: async () => {
            calls++;
            return new Response(pcm);
        },
        ...extra
    });
    return {
        engine,
        cacheDir,
        calls: () => calls
    };
}
test("WAV format and duration are accurate; reject invalid PCM", () => {
    const wav = pcmToWav(pcm);
    assert.equal(wav.toString("ascii", 0, 4), "RIFF");
    assert.equal(wav.readUInt32LE(24), 24000);
    assert.equal(wav.length, 4844);
    assert.throws(() => pcmToWav(Buffer.alloc(3)));
    assert.throws(() => pcmToWav(Buffer.alloc(0)));
    assert.throws(() => pcmToWav(Buffer.alloc(5760002)));
});
test("credentials parse as data only", () => {
    assert.equal(parseApiKey("OTHER=x\nexport ELEVENLABS_API_KEY=\"abc\"\n"), "abc");
    assert.equal(parseApiKey("OTHER=x"), undefined);
    assert.equal(parseApiKey("ELEVENLABS_API_KEY=abc # note"), "abc");
});
test("device enumeration preserves stable UIDs and rejects malformed replies", () => {
    assert.deepEqual(parseDevices('[{"uid":"BuiltInSpeakerDevice","name":"MacBook Pro Speakers"}]'), [{uid:"BuiltInSpeakerDevice",name:"MacBook Pro Speakers"}]);
    assert.deepEqual(parseDevices('[]'), []);
    assert.throws(() => parseDevices('failure'));
    assert.throws(() => parseDevices('[{"name":"Speakers"}]'));
});
test("synthesis produces secure cache, reuses same input, separates voice and model", async () => {
    const s = await setup();
    const a = await s.engine.speak({
        text: "Hello"
    });
    assert.equal(a.status, "completed");
    assert.equal(a.duration_ms, 100);
    assert.equal(a.call_received, "unverified");
    assert.equal((await readFile(a.audio_path!)).length, 4844);
    assert.equal((await stat(a.audio_path!)).mode & 511, 384);
    const b = await s.engine.speak({
        text: "Hello"
    });
    assert.equal(b.cached, true);
    assert.equal(s.calls(), 1);
    await s.engine.speak({
        text: "Hello",
        voice_id: "other"
    });
    await s.engine.speak({
        text: "Hello",
        model: "eleven_flash_v2_5"
    });
    assert.equal(s.calls(), 3);
});
test("invalid requests fail before any provider work", async () => {
    const s = await setup();
    for (const input of [{
            text: ""
        }, {
            text: "x".repeat(2001)
        }, {
            text: "x",
            voice_id: "../x"
        }, {
            text: "x",
            model: "bad"
        }, {
            text: "x",
            destination: "ctm-softphone"
        }])
        await assert.rejects(s.engine.speak(input as any));
    assert.equal(s.calls(), 0);
});
test("missing keys and provider errors are explicit and never echo secret", async () => {
    const s = await setup({
        readKey: async () => undefined
    });
    assert.match((await s.engine.speak({
        text: "x"
    })).error!, /ELEVENLABS_API_KEY/);
    const b = await setup({
        fetch: async () => new Response("secret-value", {
            status: 401
        })
    });
    const r = await b.engine.speak({
        text: "x"
    });
    assert.match(r.error!, /401/);
    assert.ok(!JSON.stringify(r).includes("secret-value"));
    const c = await setup({
        fetch: async () => {
            throw new Error("secret-value");
        }
    });
    assert.ok(!JSON.stringify(await c.engine.speak({
        text: "x"
    })).includes("secret-value"));
});
test("malformed and oversized streamed audio fail", async () => {
    for (const body of [Buffer.alloc(3), Buffer.alloc(5760002)]) {
        const s = await setup({
            fetch: async () => new Response(body)
        });
        assert.equal((await s.engine.speak({
            text: "x"
        })).status, "failed");
    }
});
test("stop while provider ignores abort cannot complete or begin playback", async () => {
    let release!: (r: Response) => void;
    let played = false;
    const s = await setup({
        fetch: () => new Promise(r => release = r),
        devices: async () => [{
                uid: "loop-2",
                name: "Loop"
            }],
        play: async () => {
            played = true;
        }
    });
    const r = await s.engine.speak({
        text: "x",
        destination: "ctm-softphone",
        output_device: "Loop",
        wait: false
    });
    while (!release)
        await new Promise(r => setImmediate(r));
    assert.equal(s.engine.stop(r.playback_id).status, "stopped");
    release(new Response(pcm));
    await s.engine.wait(r.playback_id);
    assert.equal(s.engine.status(r.playback_id).status, "stopped");
    assert.equal(played, false);
});
test("signal cancellation stops generation and unknown ids fail", async () => {
    const s = await setup({
        fetch: async (_: unknown, o: RequestInit) => new Promise((_r, j) => o.signal!.addEventListener("abort", () => j(new Error("aborted"))))
    });
    const ctrl = new AbortController();
    const r = await s.engine.speak({
        text: "x",
        wait: false
    }, ctrl.signal);
    ctrl.abort();
    assert.equal((await s.engine.wait(r.playback_id)).status, "stopped");
    assert.throws(() => s.engine.status("missing"));
});
test("API timeout bounds generation", async () => {
    const s = await setup({
        timeoutMs: 10,
        fetch: async (_: unknown, o: RequestInit) => new Promise((_r, j) => o.signal!.addEventListener("abort", () => j(new Error("aborted"))))
    });
    const r = await s.engine.speak({
        text: "x"
    });
    assert.equal(r.status, "failed");
    assert.match(r.error!, /timed out/);
});
test("routing is exact and no fallback; playback exclusive and stop survives completion", async () => {
    let done!: () => void;
    let signal!: AbortSignal;
    let selected = "";
    const s = await setup({
        devices: async () => [{
                uid: "loop-7",
                name: "Loop"
            }],
        play: async (_p: string, d: {
            uid: string;
        }, sg: AbortSignal) => {
            selected = d.uid;
            signal = sg;
            return new Promise<void>(r => done = r);
        }
    });
    const r = await s.engine.speak({
        text: "x",
        destination: "ctm-softphone",
        output_device: "Loop",
        wait: false
    });
    while (s.engine.status(r.playback_id).status === "generating")
        await new Promise(r => setImmediate(r));
    assert.equal(selected, "loop-7");
    await assert.rejects(s.engine.speak({
        text: "y",
        destination: "ctm-softphone",
        output_device: "Loop"
    }), /already/);
    s.engine.stop(r.playback_id);
    assert.equal(signal.aborted, true);
    done();
    assert.equal((await s.engine.wait(r.playback_id)).status, "stopped");
    const missing = await s.engine.speak({
        text: "x",
        destination: "ctm-softphone",
        output_device: "Loo"
    });
    assert.equal(missing.status, "failed");
});
test("duplicate device names refused and shutdown stops owned jobs", async () => {
    const s = await setup({
        devices: async () => [{
                uid: "loop-0",
                name: "Loop"
            }, {
                uid: "loop-1",
                name: "Loop"
            }]
    });
    assert.equal((await s.engine.speak({
        text: "x",
        destination: "ctm-softphone",
        output_device: "Loop"
    })).status, "failed");
    s.engine.shutdown();
    await assert.rejects(s.engine.speak({
        text: "x"
    }), /shut down/);
});
test("JSON error disguised as HTTP success is rejected", async () => {
    const s = await setup({
        fetch: async () => new Response("{}", {
            headers: {
                "content-type": "application/json"
            }
        })
    });
    assert.equal((await s.engine.speak({
        text: "x"
    })).status, "failed");
});
test("missing softphone routes fail before spending synthesis credits", async () => {
    const s = await setup({
        devices: async () => []
    });
    assert.equal((await s.engine.speak({
        text: "x",
        destination: "ctm-softphone",
        output_device: "Missing"
    })).status, "failed");
    assert.equal(s.calls(), 0);
});
test("stopping player keeps playback exclusive until it exits", async () => {
    let done!: () => void;
    const s = await setup({
        devices: async () => [{
                uid: "loop-1",
                name: "Loop"
            }],
        play: async () => new Promise<void>(r => done = r)
    });
    const a = await s.engine.speak({
        text: "x",
        destination: "ctm-softphone",
        output_device: "Loop",
        wait: false
    });
    while (!done)
        await new Promise(r => setImmediate(r));
    s.engine.stop(a.playback_id);
    await assert.rejects(s.engine.speak({
        text: "y",
        destination: "ctm-softphone",
        output_device: "Loop"
    }), /already/);
    done();
    await s.engine.wait(a.playback_id);
});
test("cache file errors are reported without synthesizing", async () => {
    const s = await setup({
        cacheDir: "/dev/null/tts-invalid"
    });
    assert.equal((await s.engine.speak({
        text: "x"
    })).status, "failed");
    assert.equal(s.calls(), 0);
});
test("shutdown cancels asynchronous work", async () => {
    const s = await setup({
        fetch: async (_: unknown, o: RequestInit) => new Promise((_r, j) => o.signal!.addEventListener("abort", () => j(new Error("aborted"))))
    });
    const a = await s.engine.speak({
        text: "x",
        wait: false
    });
    s.engine.shutdown();
    assert.equal((await s.engine.wait(a.playback_id)).status, "stopped");
});
test("device removal or replacement cannot redirect speech to a same-name device", async () => {
    let enumeration = 0;
    let played = false;
    const s = await setup({
        devices: async () => [{uid: ++enumeration === 1 ? "original" : "replacement", name:"Loop"}],
        play: async () => { played = true; }
    });
    const receipt = await s.engine.speak({text:"x",destination:"ctm-softphone",output_device:"Loop"});
    assert.equal(receipt.status,"failed");
    assert.equal(receipt.output_device_uid,"original");
    assert.equal(played,false);
});
test("device reordering preserves selected output UID", async () => {
    let enumeration = 0;
    let selected = "";
    const s = await setup({
        devices: async () => ++enumeration === 1 ? [{uid:"loop",name:"Loop"},{uid:"speakers",name:"Speakers"}] : [{uid:"speakers",name:"Speakers"},{uid:"loop",name:"Loop"}],
        play: async (_path:string,device:{uid:string}) => { selected = device.uid; }
    });
    const receipt = await s.engine.speak({text:"x",destination:"ctm-softphone",output_device:"Loop"});
    assert.equal(receipt.status,"completed");
    assert.equal(receipt.output_device_uid,"loop");
    assert.equal(selected,"loop");
});
