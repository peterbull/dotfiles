import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  assertLoopback,
  executableLines,
  getTrigger,
  interestingLogLines,
  lineCheck,
  startCommand,
  startHttp,
  stopChildren,
  triggerReport,
} from "./runme-triggers.ts";

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(check: () => boolean, ms = 5000) {
  const deadline = Date.now() + ms;
  while (!check()) {
    if (Date.now() > deadline) throw new Error("timed out");
    await wait(20);
  }
}

test("rails log filter keeps request lifecycle and errors", () => {
  const lines = interestingLogLines(
    [
      '[a] Started GET "/dashboard" for 127.0.0.1',
      "[a]   User Load (0.4ms)  SELECT ...",
      "[a] Processing by DashboardController#index as HTML",
      "[a] Redirected to https://app.ctmdev.us/users/sign_in",
      "[a] Filter chain halted as :authenticate_user! rendered or redirected",
      "[a] Completed 302 Found in 4ms",
      "NoMethodError (undefined method `x' for nil)",
    ].join("\n"),
  );
  assert.equal(lines.length, 6);
  assert.ok(!lines.some((l) => l.includes("User Load")));
});

test("executable line check uses Ruby's line table", async () => {
  const dir = mkdtempSync(join(tmpdir(), "runme-lines-"));
  const file = join(dir, "health.rb");
  writeFileSync(file, ["class Health", "  def show", "    # comment", "", "    head 200", "  end", "end", ""].join("\n"));
  const lines = await executableLines(file, dir);
  assert.ok(lines.includes(5), `line 5 executable: ${lines}`);
  assert.deepEqual(lineCheck(lines, 3), {
    line_executable: false,
    next_executable_line: 5,
    previous_executable_line: lines.filter((l) => l < 3).pop(),
  });
  assert.equal(lineCheck(lines, 5).line_executable, true);
});

test("triggers only reach loopback hosts", async () => {
  await assertLoopback("http://127.0.0.1:3000/health");
  await assertLoopback("http://localhost:3000/");
  await assert.rejects(assertLoopback("https://example.com/"), /loopback/);
  await assert.rejects(assertLoopback("file:///etc/passwd"), /http/);
});

test("http trigger returns at once and reports status plus new rails log lines", async () => {
  const root = mkdtempSync(join(tmpdir(), "runme-root-"));
  mkdirSync(join(root, "log"));
  const log = join(root, "log", "development.log");
  writeFileSync(log, '[old] Started GET "/before" for 127.0.0.1\n');
  let release: () => void = () => {};
  const server = createServer((req, res) => {
    appendFileSync(log, `[r1] Started ${req.method} "${req.url}" for 127.0.0.1\n[r1] Processing by HealthController#show as */*\n`);
    release = () => {
      appendFileSync(log, "[r1] Completed 401 Unauthorized in 4ms\n");
      res.writeHead(401, { "Content-Type": "text/plain" });
      res.end("HTTP Basic: Access denied.");
    };
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as { port: number }).port;
  try {
    const trigger = await startHttp({ method: "GET", url: `http://127.0.0.1:${port}/health` }, root);
    assert.equal(trigger.state, "pending");
    await until(() => interestingLogLines(readFileSync(log, "utf8")).length > 2);
    let report = await triggerReport(getTrigger(trigger.id)!);
    assert.equal(report.state, "pending", "held request stays pending");
    assert.deepEqual(report.rails_log_since_trigger, [
      '[r1] Started GET "/health" for 127.0.0.1',
      "[r1] Processing by HealthController#show as */*",
    ]);
    release();
    await until(() => getTrigger(trigger.id)!.state !== "pending");
    report = await triggerReport(getTrigger(trigger.id)!);
    assert.equal(report.state, "done");
    assert.equal((report as Record<string, unknown>).http_status, 401);
    assert.equal(report.rails_log_since_trigger?.at(-1), "[r1] Completed 401 Unauthorized in 4ms");
  } finally {
    server.close();
  }
});

test("command trigger runs in the background and records the exit", async () => {
  const root = mkdtempSync(join(tmpdir(), "runme-cmd-"));
  const ok = startCommand("echo enqueued", root);
  const bad = startCommand("echo nope >&2; exit 3", root);
  await until(() => ok.state !== "pending" && bad.state !== "pending");
  assert.equal(ok.state, "done");
  assert.match(String(ok.detail.output_tail), /enqueued/);
  assert.equal(bad.state, "failed");
  assert.equal(bad.detail.exit_code, 3);
  const slow = startCommand("sleep 30", root);
  stopChildren();
  await until(() => slow.state !== "pending");
  assert.equal(slow.state, "failed");
});
