import { test } from "node:test";
import assert from "node:assert/strict";
import { denyReason, prepareProdSql } from "./runme-policy.ts";

test("deny list blocks destructive and production commands", () => {
  for (const command of [
    "tmux kill-server",
    "tmux kill-session -t ctm-server",
    "ctmstop",
    "kill -9 123",
    "cd app && rm -rf tmp",
    "sudo rm file",
    "git push origin HEAD",
    "git reset --hard",
    "ssh reader 'ls'",
    "echo hi; ssh reader",
    "RAILS_ENV=production bin/rails runner 'x'",
    "mysql -u root phonetrac_dev",
    "bin/rails db:migrate",
    "docker compose down",
    "redis-cli FLUSHALL",
  ]) {
    assert.ok(denyReason(command), command);
  }
});

test("deny list ignores the same words as arguments", () => {
  for (const command of [
    "rg 'ssh reader' docs",
    "grep -n kill app/models/call.rb",
    "rg mysql config",
    "mise exec -- bundle exec rails runner 'puts Call.where(account_id: 1).to_sql'",
    "git log -5 --oneline",
  ]) {
    assert.equal(denyReason(command), undefined, command);
  }
});

test("prod SQL is single SELECT with hint and limit", () => {
  assert.equal(
    prepareProdSql("select id from calls where account_id = 1;", 50),
    "SELECT /*+ MAX_EXECUTION_TIME(3000) */ id from calls where account_id = 1 LIMIT 50",
  );
  assert.equal(
    prepareProdSql("SELECT id FROM calls LIMIT 5", 50),
    "SELECT /*+ MAX_EXECUTION_TIME(3000) */ id FROM calls LIMIT 5",
  );
  assert.equal(prepareProdSql("WITH x AS (SELECT 1) SELECT * FROM x", 10), "WITH x AS (SELECT 1) SELECT * FROM x LIMIT 10");
  assert.throws(() => prepareProdSql("DELETE FROM calls", 10));
  assert.throws(() => prepareProdSql("SELECT 1; DROP TABLE calls", 10));
  assert.throws(() => prepareProdSql("SELECT * FROM calls FOR UPDATE", 10));
  assert.throws(() => prepareProdSql("SELECT * INTO OUTFILE '/tmp/x' FROM calls", 10));
});
