import { createServer, type Server, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFile, realpath, stat } from 'node:fs/promises';
import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import twilio from 'twilio';

export interface RuntimeOptions {
  accountSid: string; apiKeySid?: string; apiSecret?: string; applicationSid: string;
  tokenProvider?: () => Promise<string>;
  identity: string; maxCallSeconds: number;
}
export interface Snapshot {
  ready: boolean; call_status: string; call_sid?: string; heartbeat_at?: number; error?: string;
}
export type Action = 'dial' | 'hangup' | 'digits' | 'play' | 'stop_audio';
interface Command { id: string; action: Action; payload: Record<string, unknown> }
interface Pending {
  command: Command; resolve: (value: Record<string, unknown>) => void;
  reject: (error: Error) => void; cleanup: () => void;
}
const base = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const statuses = new Set(['idle', 'connecting', 'ringing', 'connected', 'disconnected', 'failed']);

export class CallerRuntime {
  private server?: Server;
  private origin = '';
  private capability = randomBytes(32).toString('hex');
  private pending = new Map<string, Pending>();
  private queue: Command[] = [];
  private audio = new Map<string, string>();
  private state: Snapshot = { ready: false, call_status: 'idle' };
  private browserLease?: string;
  private lastSequence = 0;
  private dialId?: string;
  private stopped = false;
  private options: RuntimeOptions;
  constructor(options: RuntimeOptions) { this.options = options; }
  get snapshot(): Snapshot {
    const alive = this.state.heartbeat_at !== undefined && Date.now() - this.state.heartbeat_at < 5000;
    return { ...this.state, ready: this.state.ready && alive };
  }
  async start(): Promise<{ url: string }> {
    if (this.stopped) throw new Error('Caller runtime has closed; reload the extension.');
    if (!this.server) {
      this.server = createServer((req, res) => { void this.handle(req, res).catch(() => {
        if (!res.headersSent) this.send(res, 500, { error: 'Local caller request failed.' });
        else res.destroy();
      }); });
      await new Promise<void>((resolve, reject) => {
        this.server!.once('error', reject);
        this.server!.listen(0, '127.0.0.1', () => { this.server!.off('error', reject); resolve(); });
      });
      const address = this.server.address();
      if (!address || typeof address === 'string') throw new Error('No loopback listener address.');
      this.origin = `http://127.0.0.1:${address.port}`;
      this.server.unref();
    }
    return { url: `${this.origin}/#${this.capability}` };
  }
  async registerAudio(path: string): Promise<string> {
    const actual = await realpath(path);
    const info = await stat(actual);
    if (!info.isFile() || info.size < 1 || info.size > 10 * 1024 * 1024) throw new Error('Audio file must be between 1 byte and 10 MiB.');
    if (this.audio.size >= 100) throw new Error('Audio issuance limit reached; reload after hanging up.');
    const id = randomUUID(); this.audio.set(id, actual); return id;
  }
  async command(action: Action, payload: Record<string, unknown>, signal?: AbortSignal): Promise<Record<string, unknown>> {
    if (signal?.aborted) throw new Error('Caller command canceled before dispatch.');
    if (!this.snapshot.ready) throw new Error('Open caller_setup URL and click Start; caller browser is not ready.');
    if (this.pending.size >= 10) throw new Error('Caller command queue is full.');
    const command = { id: randomUUID(), action, payload };
    if (action === 'dial') { this.state.call_status = 'connecting'; this.dialId = command.id; }
    return new Promise((resolve, reject) => {
      const fail = (message: string) => {
        const delivered = !this.queue.some(c => c.id === command.id);
        this.pending.get(command.id)?.cleanup();
        this.pending.delete(command.id); this.queue = this.queue.filter(c => c.id !== command.id);
        if (delivered && (action === 'dial' || action === 'play')) this.queue.push({id:randomUUID(),action:action === 'dial' ? 'hangup' : 'stop_audio',payload:{}});
        reject(new Error(message));
      };
      const timer = setTimeout(() => fail('Caller command outcome is unknown; inspect caller_status before retrying.'), action === 'play' ? 125000 : 30000);
      const abort = () => { clearTimeout(timer); fail('Caller command canceled; outcome may be unknown. Inspect caller_status.'); };
      signal?.addEventListener('abort', abort, { once: true });
      this.pending.set(command.id, { command, resolve, reject, cleanup: () => { clearTimeout(timer); signal?.removeEventListener('abort', abort); } });
      this.queue.push(command);
    });
  }
  async close(): Promise<void> {
    if (this.snapshot.ready) {
      try { await this.command('hangup', {} , AbortSignal.timeout(2000)); }
      catch { this.state.error = 'Shutdown hangup unconfirmed; browser watchdog and provider time limit apply.'; }
    }
    this.stopped = true;
    for (const p of this.pending.values()) { p.cleanup(); p.reject(new Error('Caller runtime shut down; inspect provider before redialing.')); }
    this.pending.clear(); this.queue = [];
    this.server?.closeAllConnections();
    await new Promise<void>(resolve => this.server ? this.server.close(() => resolve()) : resolve());
    this.state.ready = false;
  }
  private send(res: ServerResponse, status: number, body: unknown): void {
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    res.end(JSON.stringify(body));
  }
  private async body(req: IncomingMessage): Promise<Record<string, unknown>> {
    let text = '';
    for await (const chunk of req) { text += chunk; if (text.length > 16384) throw new Error('Body too large.'); }
    const value: unknown = JSON.parse(text);
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid body.');
    return value as Record<string, unknown>;
  }
  private async handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    if (req.headers.host !== new URL(this.origin).host || (req.headers.origin && req.headers.origin !== this.origin)) return this.send(res, 403, { error: 'Loopback origin required.' });
    const path = new URL(req.url || '/', this.origin).pathname;
    if (req.method === 'GET' && (path === '/' || path === '/sdk.js')) {
      const file = path === '/' ? join(base, 'caller.html') : join(dirname(require.resolve('@twilio/voice-sdk')), '../dist/twilio.min.js');
      res.writeHead(200, { 'Content-Type': path === '/' ? 'text/html' : 'text/javascript', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; connect-src 'self' https://*.twilio.com wss://*.twilio.com; media-src 'self' blob:; style-src 'unsafe-inline'" });
      res.end(await readFile(file)); return;
    }
    const auth = req.headers['x-caller-capability'];
    if (typeof auth !== 'string' || auth.length !== this.capability.length || !timingSafeEqual(Buffer.from(auth), Buffer.from(this.capability))) return this.send(res, 403, { error: 'Caller capability required.' });
    if (req.method === 'POST' && path === '/api/claim') {
      if (this.browserLease) return this.send(res, 409, { error: 'A caller page already owns this runtime. Reload the pi extension to replace it.' });
      this.browserLease = randomUUID(); this.send(res, 200, { lease: this.browserLease, maxCallSeconds: this.options.maxCallSeconds }); return;
    }
    if (req.headers['x-caller-lease'] !== this.browserLease || !this.browserLease) return this.send(res, 403, { error: 'Caller browser lease required.' });
    if (req.method === 'GET' && path === '/api/token') {
      if (this.options.tokenProvider) { this.send(res, 200, { token: await this.options.tokenProvider() }); return; }
      if (!this.options.apiKeySid || !this.options.apiSecret) return this.send(res, 503, {error:'Voice SDK signing credentials unavailable.'});
      const AccessToken = twilio.jwt.AccessToken;
      const token = new AccessToken(this.options.accountSid, this.options.apiKeySid, this.options.apiSecret, { identity: this.options.identity, ttl: 600 });
      token.addGrant(new AccessToken.VoiceGrant({ outgoingApplicationSid: this.options.applicationSid, incomingAllow: false }));
      this.send(res, 200, { token: token.toJwt() }); return;
    }
    if (req.method === 'GET' && path === '/api/commands') {
      this.state.heartbeat_at = Date.now(); this.send(res, 200, { commands: this.queue.splice(0) }); return;
    }
    if (req.method === 'POST' && path === '/api/event') {
      const event = await this.body(req);
      const snapshot = event.snapshot as Record<string, unknown> | undefined;
      if (snapshot && (!this.dialId || snapshot.dial_id === this.dialId) && typeof event.sequence === 'number' && Number.isSafeInteger(event.sequence) && event.sequence > this.lastSequence && typeof snapshot.call_status === 'string' && statuses.has(snapshot.call_status)) {
        this.lastSequence = event.sequence;
        this.state = { ready: snapshot.ready === true, call_status: snapshot.call_status, heartbeat_at: Date.now(),
          ...(typeof snapshot.call_sid === 'string' && /^CA[0-9a-f]{32}$/i.test(snapshot.call_sid) ? { call_sid: snapshot.call_sid } : {}) };
      }
      if (typeof event.id === 'string') {
        const pending = this.pending.get(event.id);
        if (pending) {
          pending.cleanup(); this.pending.delete(event.id);
          if (event.ok === true) pending.resolve((event.result && typeof event.result === 'object' ? event.result : {}) as Record<string, unknown>);
          else pending.reject(new Error('Caller browser operation failed; inspect the caller page.'));
        }
      }
      this.send(res, 200, { ok: true }); return;
    }
    if (req.method === 'GET' && path.startsWith('/audio/')) {
      const id = path.slice(7); const file = this.audio.get(id);
      if (!file) return this.send(res, 404, { error: 'Unknown issued audio.' });
      res.writeHead(200, { 'Content-Type': file.toLowerCase().endsWith('.mp3') ? 'audio/mpeg' : 'audio/wav', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      res.end(await readFile(file)); return;
    }
    this.send(res, 404, { error: 'Unknown caller endpoint.' });
  }
}
