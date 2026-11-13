import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import { denyReason, prepareProdSql, PROD_TIMEOUT_MS } from "./runme-policy.ts";
import {
  assertLoopback,
  browserCookies,
  executableLines,
  getTrigger,
  lineCheck,
  logCursor,
  refreshCall,
  startBrowser,
  startCall,
  startCommand,
  startHttp,
  stopChildren,
  triggerReport,
  type Trigger,
} from "./runme-triggers.ts";

// RunMe's Neovim panel owns this process over `pi --mode rpc`. Bridge calls ride
// the extension UI sub-protocol: an `input` dialog titled BRIDGE_TITLE carries a
// JSON request that nvim answers asynchronously, so no socket is needed and
// long waits (a breakpoint hit) do not block the editor.
const BRIDGE_TITLE = "runme:bridge";
const BRIDGE_TIMEOUT_MS = 15_000;

const PROD_ROW_CEILING = Number(process.env.RUNME_PROD_ROW_CEILING || 1_000_000);
const PROD_APP_DIR = "/var/www/apps/phonetrac/current";

function prodScript(sql: string, phase: "explain" | "run"): string {
  const encoded = Buffer.from(sql, "utf8").toString("base64");
  const body =
    phase === "explain"
      ? `out = { explain: connection.select_all("EXPLAIN " + sql).to_a }`
      : `started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = connection.select_all(sql)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
    out = { columns: result.columns, rows: result.rows.map { |r| r.map { |v| v.nil? ? nil : v.to_s[0, 500] } }, ms: elapsed }`;
  return `require "base64"
require "json"
sql = Base64.strict_decode64("${encoded}").force_encoding("UTF-8")
connection = ActiveRecord::Base.connection
previous = connection.select_value("SELECT @@session.max_execution_time").to_i
begin
  connection.execute("SET SESSION max_execution_time = ${PROD_TIMEOUT_MS}")
  raise "Timeout not applied" if connection.select_value("SELECT @@session.max_execution_time").to_i != ${PROD_TIMEOUT_MS}
  ${body}
  STDOUT.puts "RUNME_JSON:" + JSON.generate(out)
ensure
  connection.execute("SET SESSION max_execution_time = #{previous}")
end
`;
}

function runOnReader(script: string, signal?: AbortSignal): Promise<any> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "ssh",
      [
        "-T",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=8",
        "-o",
        "ClearAllForwardings=yes",
        "reader",
        `cd ${PROD_APP_DIR} && RAILS_ENV=production bundle exec bin/query --no-print`,
      ],
      { signal, stdio: ["pipe", "pipe", "pipe"] },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("error", reject);
    child.on("close", (code) => {
      const line = stdout.split("\n").find((l) => l.startsWith("RUNME_JSON:"));
      if (code !== 0 || !line) {
        reject(new Error(`reader exited ${code}: ${(stderr || stdout).trim().slice(-2000)}`));
        return;
      }
      resolve(JSON.parse(line.slice("RUNME_JSON:".length)));
    });
    child.stdin.end(script);
  });
}

async function bridge(ctx: ExtensionContext, op: string, args: object = {}, timeoutMs = BRIDGE_TIMEOUT_MS): Promise<any> {
  const reply = await ctx.ui.input(BRIDGE_TITLE, JSON.stringify({ op, args }), {
    timeout: timeoutMs,
    signal: ctx.signal,
  });
  if (reply === undefined) throw new Error(`nvim did not answer ${op} (timeout or cancelled)`);
  const parsed = JSON.parse(reply);
  if (!parsed.ok) throw new Error(parsed.error || `${op} failed`);
  return parsed.result;
}

function started(trigger: Trigger) {
  return text({
    trigger_id: trigger.id,
    label: trigger.label,
    next: "Call runme_wait_stopped now; if it times out, call runme_trigger_status with this trigger_id to diagnose.",
  });
}

function text(value: unknown) {
  return {
    content: [{ type: "text" as const, text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
    details: {},
  };
}

export default function (pi: ExtensionAPI) {
  pi.on("session_shutdown", () => stopChildren());

  pi.on("tool_call", async (event) => {
    if (!isToolCallEventType("bash", event)) return;
    const command = event.input.command;
    const reason = denyReason(command);
    if (reason) return { block: true, reason: `RunMe blocked this command: ${reason}` };
  });

  pi.registerTool({
    name: "runme_plan",
    label: "Plan",
    description: "Show the numbered plan for this run in the RunMe panel. Call once before acting.",
    promptSnippet: "Show the run plan in the editor panel",
    parameters: Type.Object({ steps: Type.Array(Type.String(), { minItems: 1 }) }),
    async execute() {
      return text("plan shown");
    },
  });

  pi.registerTool({
    name: "runme_step",
    label: "Step",
    description: "Update the status of one plan step (1-based index) in the RunMe panel.",
    parameters: Type.Object({
      index: Type.Integer({ minimum: 1 }),
      status: StringEnum(["running", "done", "failed", "skipped"] as const),
      note: Type.Optional(Type.String()),
    }),
    async execute() {
      return text("step updated");
    },
  });

  pi.registerTool({
    name: "runme_result",
    label: "Result",
    description:
      "Show the result of the run in the RunMe panel: a table (columns + rows) and/or text. Include `query` with the exact SQL or Ruby that produced it so the user can edit and re-run it.",
    parameters: Type.Object({
      title: Type.String(),
      text: Type.Optional(Type.String()),
      columns: Type.Optional(Type.Array(Type.String())),
      rows: Type.Optional(Type.Array(Type.Array(Type.Union([Type.String(), Type.Number(), Type.Null(), Type.Boolean()])))),
      query: Type.Optional(Type.String()),
      language: Type.Optional(StringEnum(["sql", "ruby", "json", "text"] as const)),
      target: Type.Optional(StringEnum(["local", "prod"] as const)),
    }),
    async execute() {
      return text("result shown");
    },
  });

  pi.registerTool({
    name: "runme_context",
    label: "Editor context",
    description: "Read the user's current editor context again (file, cursor, enclosing symbol, detected query, debugger state).",
    parameters: Type.Object({}),
    async execute(_id, _params, _signal, _onUpdate, ctx) {
      return text(await bridge(ctx, "context"));
    },
  });

  pi.registerTool({
    name: "runme_dap_status",
    label: "Debugger status",
    description: "Return nvim-dap session state: attached?, port, stopped frame, and breakpoints.",
    parameters: Type.Object({}),
    async execute(_id, _params, _signal, _onUpdate, ctx) {
      return text(await bridge(ctx, "dap_status"));
    },
  });

  pi.registerTool({
    name: "runme_dap_attach",
    label: "Attach debugger",
    description:
      "Attach the user's nvim-dap to a running rdbg: `rails` (port 38698, web requests) or `worker` (port 38699, resque jobs). No-op when already attached to that port.",
    parameters: Type.Object({
      target: StringEnum(["rails", "worker", "port"] as const),
      port: Type.Optional(Type.Integer()),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      return text(await bridge(ctx, "dap_attach", params, 20_000));
    },
  });

  pi.registerTool({
    name: "runme_breakpoint",
    label: "Set breakpoint",
    description:
      "Set a breakpoint in the user's nvim-dap. Prefer a `condition` (Ruby expression) that matches only the requested entity so unrelated dev traffic is not suspended.",
    parameters: Type.Object({
      file: Type.String({ description: "Absolute path or path relative to the project root" }),
      line: Type.Integer({ minimum: 1 }),
      condition: Type.Optional(Type.String()),
      hit_condition: Type.Optional(Type.String()),
      log_message: Type.Optional(Type.String()),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const result = await bridge(ctx, "breakpoint_set", params);
      if (String(result.file).endsWith(".rb")) {
        try {
          const check = lineCheck(await executableLines(result.file, ctx.cwd), result.line);
          Object.assign(result, check, { will_stop: check.line_executable });
          if (!check.line_executable) {
            await bridge(ctx, "breakpoint_remove", { file: result.file, line: result.line });
            result.set = false;
            result.warning = `Line ${result.line} has no executable code, so the debugger cannot stop on it; RunMe removed it. Set it on line ${check.next_executable_line ?? check.previous_executable_line} (or another line in the same method).`;
          }
        } catch (error) {
          result.line_check_error = (error as Error).message;
        }
      }
      return text(result);
    },
  });

  pi.registerTool({
    name: "runme_breakpoint_clear",
    label: "Clear breakpoints",
    description: "Remove every breakpoint RunMe set in this run. The user's own breakpoints stay.",
    parameters: Type.Object({}),
    async execute(_id, _params, _signal, _onUpdate, ctx) {
      return text(await bridge(ctx, "breakpoint_clear"));
    },
  });

  pi.registerTool({
    name: "runme_wait_stopped",
    label: "Wait for breakpoint",
    description: "Wait until the debugger stops (breakpoint hit). Returns file, line, thread. Trigger the flow before or while waiting.",
    parameters: Type.Object({ timeout_s: Type.Optional(Type.Integer({ minimum: 1, maximum: 1800 })) }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const timeout = params.timeout_s ?? 300;
      return text(await bridge(ctx, "wait_stopped", { timeout_s: timeout }, timeout * 1000 + 5000));
    },
  });

  pi.registerTool({
    name: "runme_dap_eval",
    label: "Evaluate",
    description: "Evaluate a Ruby expression in the stopped frame of the user's debugger session. Read values only; never mutate state.",
    parameters: Type.Object({ expression: Type.String() }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      return text(await bridge(ctx, "dap_eval", params));
    },
  });

  pi.registerTool({
    name: "runme_handoff",
    label: "Hand off",
    description:
      "Give the stopped debugger to the user: opens dap-ui at the stop location and shows `message`. Ends your turn; do not continue or detach afterwards.",
    parameters: Type.Object({ message: Type.String() }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      await bridge(ctx, "handoff", params);
      return { ...text("handed off to the user"), terminate: true };
    },
  });

  pi.registerTool({
    name: "runme_dap_continue",
    label: "Continue",
    description:
      "Resume a thread that stopped somewhere other than your breakpoint (a user breakpoint or an exception) so the flow can reach your breakpoint. Refused after runme_handoff.",
    parameters: Type.Object({ reason: Type.String() }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      return text(await bridge(ctx, "continue", params));
    },
  });

  pi.registerTool({
    name: "runme_trigger_browser",
    label: "Trigger: browser",
    description:
      "Open a local app URL in the dedicated, logged-in agent Chrome (background tab, reused across calls), or run `script` (an async function body, e.g. a fetch() to a JSON/GraphQL endpoint) inside a page at that URL's origin so it uses the browser session and CSRF token. Returns at once with a trigger_id; the request may be held by the breakpoint.",
    parameters: Type.Object({
      url: Type.String({ description: "Local app URL, e.g. https://app.ctmdev.us/dashboard" }),
      script: Type.Optional(Type.String()),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      await assertLoopback(params.url);
      return started(await startBrowser(params, ctx.cwd));
    },
  });

  pi.registerTool({
    name: "runme_trigger_http",
    label: "Trigger: HTTP",
    description:
      "Send one HTTP request to the local stack in the background (loopback hosts only, redirects not followed). Use basic_auth for API keys, or browser_session=true to send the agent Chrome's cookies for session-authenticated endpoints. Returns at once with a trigger_id.",
    parameters: Type.Object({
      method: StringEnum(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"] as const),
      url: Type.String(),
      headers: Type.Optional(Type.Record(Type.String(), Type.String())),
      body: Type.Optional(Type.String()),
      basic_auth: Type.Optional(Type.Object({ user: Type.String(), password: Type.String() })),
      browser_session: Type.Optional(Type.Boolean()),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      await assertLoopback(params.url);
      const cookie = params.browser_session ? await browserCookies(params.url) : undefined;
      return started(await startHttp({ ...params, cookie }, ctx.cwd));
    },
  });

  pi.registerTool({
    name: "runme_trigger_command",
    label: "Trigger: command",
    description:
      "Start a local shell command in the background, e.g. `mise exec -- bundle exec rails runner 'Resque.enqueue(SomeJob, 1)'` to have the debugged resque worker run a job. Same safety rules as bash. Returns at once with a trigger_id.",
    parameters: Type.Object({ command: Type.String() }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const reason = denyReason(params.command);
      if (reason) throw new Error(`RunMe blocked this command: ${reason}`);
      const cursor = await logCursor(ctx.cwd);
      return started(startCommand(params.command, ctx.cwd, cursor.logPath, cursor.logOffset));
    },
  });

  pi.registerTool({
    name: "runme_trigger_call",
    label: "Trigger: phone call",
    description:
      "Place a simulated customer call through the local synthetic-user runner (same arguments as its synthetic_run: `call` with prompt, firstMessage, mode phone|room, conversationSeconds, persona, environment; or `scenarioPath`). Use for call routing, IVR, VoiceAI and Twilio webhook code. Returns a trigger_id.",
    parameters: Type.Object({
      call: Type.Optional(Type.Record(Type.String(), Type.Any())),
      scenarioPath: Type.Optional(Type.String()),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      return started(await startCall(params, ctx.cwd));
    },
  });

  pi.registerTool({
    name: "runme_trigger_status",
    label: "Trigger status",
    description:
      "Report a trigger: pending/done/failed, HTTP or document status, redirect location, script or command output, call status, and the Rails development.log lines written since the trigger (Started / Processing by / Completed / errors). Use it to prove whether the request reached the debugged process and which action handled it.",
    parameters: Type.Object({ trigger_id: Type.String() }),
    async execute(_id, params) {
      const trigger = getTrigger(params.trigger_id);
      if (!trigger) throw new Error(`unknown trigger ${params.trigger_id}`);
      await refreshCall(trigger);
      return text(await triggerReport(trigger));
    },
  });

  pi.registerTool({
    name: "runme_prod_sql",
    label: "Prod SQL",
    description: `Run one read-only SELECT on the production MySQL reader through bin/query. RunMe adds MAX_EXECUTION_TIME(${PROD_TIMEOUT_MS}) and a LIMIT, runs EXPLAIN first, refuses plans that estimate more than ${PROD_ROW_CEILING} rows in one table, then asks the user to approve. Never use it to choose samples by scanning big tables.`,
    parameters: Type.Object({
      sql: Type.String(),
      purpose: Type.String({ description: "One line shown to the user in the approval prompt" }),
      limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 1000 })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      const sql = prepareProdSql(params.sql, params.limit ?? 200);
      onUpdate?.(text(`EXPLAIN on reader…\n${sql}`));
      const { explain } = await runOnReader(prodScript(sql, "explain"), signal);
      const estimates = (explain as Array<Record<string, any>>).map((row) => ({
        table: row.table,
        type: row.type,
        key: row.key,
        rows: Number(row.rows ?? 0),
        extra: row.Extra,
      }));
      const worst = Math.max(0, ...estimates.map((e) => e.rows));
      const plan = estimates.map((e) => `${e.table}: ${e.type} key=${e.key ?? "NONE"} rows≈${e.rows} ${e.extra ?? ""}`).join("\n");
      if (worst > PROD_ROW_CEILING) {
        throw new Error(`EXPLAIN estimates ${worst} rows (ceiling ${PROD_ROW_CEILING}). Narrow the query.\n${plan}`);
      }
      const approved = await ctx.ui.confirm(
        "Run on PROD reader?",
        `${params.purpose}\n\n${sql}\n\nEXPLAIN:\n${plan}`,
        { signal },
      );
      if (!approved) throw new Error("The user declined the production query");
      const result = await runOnReader(prodScript(sql, "run"), signal);
      return {
        content: [{ type: "text" as const, text: JSON.stringify({ sql, explain: plan, ...result }) }],
        details: { sql, explain: estimates, ...result },
      };
    },
  });
}
