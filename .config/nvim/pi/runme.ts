import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import { denyReason, isReadOnlyCommand, prepareProdSql, PROD_TIMEOUT_MS } from "./runme-policy.ts";

// RunMe's Neovim panel owns this process over `pi --mode rpc`. Bridge calls ride
// the extension UI sub-protocol: an `input` dialog titled BRIDGE_TITLE carries a
// JSON request that nvim answers asynchronously, so no socket is needed and
// long waits (a breakpoint hit) do not block the editor.
const BRIDGE_TITLE = "runme:bridge";
const BRIDGE_TIMEOUT_MS = 15_000;

const APPROVE_LOCAL = process.env.RUNME_APPROVE_LOCAL === "1";
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

function text(value: unknown) {
  return {
    content: [{ type: "text" as const, text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
    details: {},
  };
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;
    const command = event.input.command;
    const reason = denyReason(command);
    if (reason) return { block: true, reason: `RunMe blocked this command: ${reason}` };
    if (APPROVE_LOCAL || isReadOnlyCommand(command)) return;
    const approved = await ctx.ui.confirm("Run local command?", command);
    if (!approved) return { block: true, reason: "The user declined this command" };
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
      return text(await bridge(ctx, "breakpoint_set", params));
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
