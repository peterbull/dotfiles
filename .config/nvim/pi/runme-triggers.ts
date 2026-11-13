import { lookup } from "node:dns/promises";
import { spawn, type ChildProcess } from "node:child_process";
import { open, readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

export type TriggerKind = "http" | "browser" | "command" | "call";
export type TriggerState = "pending" | "done" | "failed";

export interface Trigger {
  id: string;
  kind: TriggerKind;
  label: string;
  started: number;
  finished?: number;
  state: TriggerState;
  detail: Record<string, unknown>;
  logPath?: string;
  logOffset?: number;
}

const triggers = new Map<string, Trigger>();
const children = new Set<ChildProcess>();
let sequence = 0;

const INTERESTING_LOG =
  /Started (GET|POST|PUT|PATCH|DELETE|HEAD)|Processing by|Completed \d{3}|Redirected to|Filter chain halted|Can't verify CSRF|RoutingError|Error \(|Exception|\b\w+Error\b|Enqueued|Performing|Performed|resque/i;
const MAX_LOG_LINES = 40;
const MAX_LOG_BYTES = 256 * 1024;

function newTrigger(kind: TriggerKind, label: string, logPath?: string, logOffset?: number): Trigger {
  sequence += 1;
  const trigger: Trigger = {
    id: `${kind}-${sequence}`,
    kind,
    label,
    started: Date.now(),
    state: "pending",
    detail: {},
    logPath,
    logOffset,
  };
  triggers.set(trigger.id, trigger);
  return trigger;
}

function finish(trigger: Trigger, state: TriggerState, detail: Record<string, unknown>) {
  trigger.state = state;
  trigger.finished = Date.now();
  Object.assign(trigger.detail, detail);
}

export function getTrigger(id: string): Trigger | undefined {
  return triggers.get(id);
}

export function interestingLogLines(text: string): string[] {
  const lines = text.split("\n").filter((line) => INTERESTING_LOG.test(line));
  return lines.length > MAX_LOG_LINES ? lines.slice(-MAX_LOG_LINES) : lines;
}

export async function logCursor(root: string): Promise<{ logPath?: string; logOffset?: number }> {
  const logPath = join(root, "log", "development.log");
  try {
    return { logPath, logOffset: (await stat(logPath)).size };
  } catch {
    return {};
  }
}

async function logSince(trigger: Trigger): Promise<string[] | undefined> {
  if (!trigger.logPath || trigger.logOffset === undefined) return undefined;
  const handle = await open(trigger.logPath, "r");
  try {
    const size = (await handle.stat()).size;
    const start = Math.max(trigger.logOffset, size - MAX_LOG_BYTES);
    const length = size - start;
    if (length <= 0) return [];
    const buffer = Buffer.alloc(length);
    await handle.read(buffer, 0, length, start);
    return interestingLogLines(buffer.toString("utf8"));
  } finally {
    await handle.close();
  }
}

export async function triggerReport(trigger: Trigger) {
  const end = trigger.finished ?? Date.now();
  let log: string[] | undefined;
  let logError: string | undefined;
  try {
    log = await logSince(trigger);
  } catch (error) {
    logError = (error as Error).message;
  }
  return {
    id: trigger.id,
    kind: trigger.kind,
    label: trigger.label,
    state: trigger.state,
    elapsed_ms: end - trigger.started,
    ...trigger.detail,
    rails_log_since_trigger: log,
    rails_log_error: logError,
  };
}

export async function assertLoopback(url: string): Promise<URL> {
  const parsed = new URL(url);
  if (!/^https?:$/.test(parsed.protocol)) throw new Error(`only http(s) URLs are allowed: ${url}`);
  const host = parsed.hostname.replace(/^\[|\]$/g, "");
  const addresses = await lookup(host, { all: true });
  const local = addresses.length > 0 && addresses.every((a) => a.address === "::1" || a.address.startsWith("127."));
  if (!local) throw new Error(`${host} does not resolve to loopback; RunMe triggers only reach the local stack`);
  return parsed;
}

function clip(text: string, max: number): string {
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

export interface HttpTriggerInput {
  method: string;
  url: string;
  headers?: Record<string, string>;
  body?: string;
  basic_auth?: { user: string; password: string };
  cookie?: string;
}

export async function startHttp(input: HttpTriggerInput, root: string): Promise<Trigger> {
  const url = await assertLoopback(input.url);
  const cursor = await logCursor(root);
  const trigger = newTrigger("http", `${input.method} ${url.href}`, cursor.logPath, cursor.logOffset);
  const headers: Record<string, string> = { "User-Agent": "runme-trigger", ...input.headers };
  if (input.basic_auth) {
    headers.Authorization = `Basic ${Buffer.from(`${input.basic_auth.user}:${input.basic_auth.password}`).toString("base64")}`;
  }
  if (input.cookie) headers.Cookie = input.cookie;
  fetch(url, {
    method: input.method,
    headers,
    body: input.body,
    redirect: "manual",
    signal: AbortSignal.timeout(30 * 60_000),
  })
    .then(async (response) => {
      const text = await response.text();
      finish(trigger, "done", {
        http_status: response.status,
        location: response.headers.get("location") ?? undefined,
        body: clip(text, 1500),
      });
    })
    .catch((error) => finish(trigger, "failed", { error: (error as Error).cause ?? (error as Error).message }));
  return trigger;
}

export function startCommand(command: string, root: string, logPath?: string, logOffset?: number): Trigger {
  const trigger = newTrigger("command", command, logPath, logOffset);
  const child = spawn("bash", ["-lc", command], { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
  children.add(child);
  let output = "";
  const append = (chunk: Buffer) => {
    output = (output + chunk.toString("utf8")).slice(-4000);
  };
  child.stdout.on("data", append);
  child.stderr.on("data", append);
  child.on("error", (error) => finish(trigger, "failed", { error: error.message }));
  child.on("close", (code) => {
    children.delete(child);
    finish(trigger, code === 0 ? "done" : "failed", { exit_code: code, output_tail: output });
  });
  return trigger;
}

export function stopChildren() {
  for (const child of children) child.kill("SIGTERM");
  children.clear();
  if (browser && !browser.closed && tab) {
    const cdp = browser;
    cdp.send("Target.closeTarget", { targetId: tab.targetId }).finally(() => cdp.close());
  } else {
    browser?.close();
  }
  browser = undefined;
  tab = undefined;
}

// Chrome DevTools Protocol over the dedicated agent Chrome. Navigation is sent
// without awaiting it, because a breakpoint holds the server response and the
// agent must be free to call runme_wait_stopped meanwhile.

type CdpHandler = (params: any, sessionId?: string) => void;

class Cdp {
  private socket: WebSocket;
  private nextId = 0;
  private pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
  private handlers = new Map<string, Set<CdpHandler>>();
  closed = false;

  private constructor(socket: WebSocket) {
    this.socket = socket;
    socket.addEventListener("message", (event) => {
      const msg = JSON.parse(String(event.data));
      if (msg.id !== undefined) {
        const entry = this.pending.get(msg.id);
        if (!entry) return;
        this.pending.delete(msg.id);
        if (msg.error) entry.reject(new Error(msg.error.message));
        else entry.resolve(msg.result);
        return;
      }
      for (const handler of this.handlers.get(msg.method) ?? []) handler(msg.params, msg.sessionId);
    });
    socket.addEventListener("close", () => {
      this.closed = true;
      for (const entry of this.pending.values()) entry.reject(new Error("DevTools connection closed"));
      this.pending.clear();
    });
  }

  static async connect(endpoint: string): Promise<Cdp> {
    const version = await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(3000) }).then((r) => r.json());
    const socket = new WebSocket(version.webSocketDebuggerUrl);
    await new Promise<void>((resolve, reject) => {
      socket.addEventListener("open", () => resolve(), { once: true });
      socket.addEventListener("error", () => reject(new Error(`cannot connect to Chrome DevTools at ${endpoint}`)), { once: true });
    });
    return new Cdp(socket);
  }

  send(method: string, params: object = {}, sessionId?: string): Promise<any> {
    this.nextId += 1;
    const id = this.nextId;
    this.socket.send(JSON.stringify({ id, method, params, sessionId }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }

  on(method: string, handler: CdpHandler): () => void {
    const set = this.handlers.get(method) ?? new Set();
    set.add(handler);
    this.handlers.set(method, set);
    return () => set.delete(handler);
  }

  close() {
    this.socket.close();
  }
}

let browser: Cdp | undefined;
let tab: { targetId: string; sessionId: string } | undefined;

export const CHROME_ENDPOINT = process.env.RUNME_CHROME_ENDPOINT || "http://127.0.0.1:9223";

async function browserTab(): Promise<{ cdp: Cdp; sessionId: string }> {
  if (!browser || browser.closed) {
    browser = await Cdp.connect(CHROME_ENDPOINT);
    tab = undefined;
  }
  const cdp = browser;
  if (tab) {
    const { targetInfos } = await cdp.send("Target.getTargets");
    if (!targetInfos.some((t: any) => t.targetId === tab!.targetId)) tab = undefined;
  }
  if (!tab) {
    const { targetId } = await cdp.send("Target.createTarget", { url: "about:blank", background: true });
    const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
    await cdp.send("Page.enable", {}, sessionId);
    await cdp.send("Network.enable", {}, sessionId);
    await cdp.send("Runtime.enable", {}, sessionId);
    tab = { targetId, sessionId };
  }
  return { cdp, sessionId: tab.sessionId };
}

export async function browserCookies(url: string): Promise<string> {
  const { cdp, sessionId } = await browserTab();
  const { cookies } = await cdp.send("Network.getCookies", { urls: [url] }, sessionId);
  return (cookies as Array<{ name: string; value: string }>).map((c) => `${c.name}=${c.value}`).join("; ");
}

async function currentUrl(cdp: Cdp, sessionId: string): Promise<string> {
  const { result } = await cdp.send("Runtime.evaluate", { expression: "location.href", returnByValue: true }, sessionId);
  return String(result.value ?? "");
}

function watchNavigation(cdp: Cdp, sessionId: string, trigger: Trigger): Promise<void> {
  return new Promise((resolve) => {
    const offs: Array<() => void> = [];
    const done = () => {
      offs.forEach((off) => off());
      resolve();
    };
    offs.push(
      cdp.on("Network.responseReceived", (params, sid) => {
        if (sid !== sessionId || params.type !== "Document") return;
        Object.assign(trigger.detail, { document_status: params.response.status, document_url: params.response.url });
      }),
      cdp.on("Network.loadingFailed", (params, sid) => {
        if (sid !== sessionId || params.type !== "Document") return;
        Object.assign(trigger.detail, { navigation_error: params.errorText });
      }),
      cdp.on("Page.loadEventFired", (_params, sid) => {
        if (sid !== sessionId) return;
        trigger.detail.loaded = true;
        done();
      }),
    );
    setTimeout(done, 30 * 60_000);
  });
}

export async function startBrowser(input: { url: string; script?: string }, root: string): Promise<Trigger> {
  const target = await assertLoopback(input.url);
  const { cdp, sessionId } = await browserTab();
  const cursor = await logCursor(root);
  const trigger = newTrigger("browser", input.script ? `script on ${target.origin}` : `open ${target.href}`, cursor.logPath, cursor.logOffset);

  const navigate = async () => {
    const loaded = watchNavigation(cdp, sessionId, trigger);
    const result = await cdp.send("Page.navigate", { url: target.href }, sessionId);
    if (result.errorText) throw new Error(result.errorText);
    return loaded;
  };

  const run = async () => {
    if (!input.script) {
      await navigate();
      if (trigger.detail.navigation_error) throw new Error(String(trigger.detail.navigation_error));
      return;
    }
    const here = await currentUrl(cdp, sessionId).catch(() => "");
    if (!here.startsWith(target.origin)) await navigate();
    const { result, exceptionDetails } = await cdp.send(
      "Runtime.evaluate",
      {
        expression: `(async () => { ${input.script} })().then((value) => JSON.stringify(value ?? null))`,
        awaitPromise: true,
        returnByValue: true,
      },
      sessionId,
    );
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description ?? exceptionDetails.text);
    trigger.detail.script_result = clip(String(result.value ?? ""), 1500);
  };

  run()
    .then(() => finish(trigger, "done", {}))
    .catch((error) => finish(trigger, "failed", { error: (error as Error).message }));
  return trigger;
}

// synthetic-user runs as a local streamable-HTTP MCP server. The bearer token is
// read here so it never enters the model context.

export const SYNTHETIC_URL = process.env.RUNME_SYNTHETIC_URL || "http://127.0.0.1:7391/mcp";

async function syntheticToken(): Promise<string> {
  if (process.env.RUNME_SYNTHETIC_TOKEN) return `Bearer ${process.env.RUNME_SYNTHETIC_TOKEN}`;
  const config = JSON.parse(await readFile(join(homedir(), ".claude.json"), "utf8"));
  const find = (node: any): string | undefined => {
    if (!node || typeof node !== "object") return undefined;
    const server = node.mcpServers?.["synthetic-user"];
    if (server?.headers?.Authorization) return server.headers.Authorization;
    for (const value of Object.values(node)) {
      const found = find(value);
      if (found) return found;
    }
    return undefined;
  };
  const token = find(config);
  if (!token) throw new Error("no synthetic-user token: set RUNME_SYNTHETIC_TOKEN or configure the synthetic-user MCP in Claude Code");
  return token;
}

export async function callSynthetic(tool: string, args: object): Promise<any> {
  const response = await fetch(SYNTHETIC_URL, {
    method: "POST",
    headers: {
      Authorization: await syntheticToken(),
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: tool, arguments: args } }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) throw new Error(`synthetic-user ${tool}: HTTP ${response.status}`);
  const text = await response.text();
  const payload = text.trimStart().startsWith("{")
    ? JSON.parse(text)
    : JSON.parse(
        text
          .split("\n")
          .filter((line) => line.startsWith("data: "))
          .map((line) => line.slice(6))
          .pop() ?? "{}",
      );
  if (payload.error) throw new Error(`synthetic-user ${tool}: ${payload.error.message}`);
  const result = payload.result ?? {};
  const body = (result.content ?? []).map((c: any) => c.text ?? "").join("\n");
  if (result.isError) throw new Error(`synthetic-user ${tool}: ${body}`);
  try {
    return JSON.parse(body);
  } catch {
    return body;
  }
}

export async function startCall(args: object, root: string): Promise<Trigger> {
  const cursor = await logCursor(root);
  const trigger = newTrigger("call", "synthetic-user call", cursor.logPath, cursor.logOffset);
  const started = await callSynthetic("synthetic_run", args);
  const runId = typeof started === "object" ? (started.id ?? started.runId) : undefined;
  trigger.detail.run_id = runId;
  trigger.detail.started = started;
  return trigger;
}

export async function refreshCall(trigger: Trigger) {
  if (trigger.kind !== "call" || !trigger.detail.run_id || trigger.state !== "pending") return;
  const status = await callSynthetic("synthetic_status", { id: trigger.detail.run_id });
  trigger.detail.status = status;
  const runStatus = typeof status === "object" ? status.status : undefined;
  if (["passed", "failed", "inconclusive", "canceled"].includes(runStatus)) finish(trigger, "done", {});
}

// Ruby's own line table decides whether rdbg can stop on a line; rdbg reports
// every breakpoint in a locatable file as verified.
const LINE_SCRIPT =
  'iseq = RubyVM::InstructionSequence.compile_file(ARGV[0]); lines = []; walk = ->(i) { i.trace_points.each { |l, e| lines << l if e == :line }; i.each_child { |c| walk.(c) } }; walk.(iseq); puts lines.uniq.sort.join(",")';

export function executableLines(file: string, root: string): Promise<number[]> {
  return new Promise((resolve, reject) => {
    const child = spawn("mise", ["exec", "--", "ruby", "-e", LINE_SCRIPT, file], { cwd: root });
    let out = "";
    let err = "";
    child.stdout.on("data", (c) => (out += c));
    child.stderr.on("data", (c) => (err += c));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) reject(new Error(err.trim() || `ruby exited ${code}`));
      else resolve(out.trim() === "" ? [] : out.trim().split(",").map(Number));
    });
  });
}

export function lineCheck(lines: number[], line: number) {
  const executable = lines.includes(line);
  const next = lines.find((l) => l > line);
  const previous = [...lines].reverse().find((l) => l < line);
  return { line_executable: executable, next_executable_line: next, previous_executable_line: previous };
}
