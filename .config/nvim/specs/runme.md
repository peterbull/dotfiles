# RunMe — live, context-aware "run this and show me" for Neovim

Status: implemented (query, break, observe, prod-reader query, follow-ups, history).

From any buffer, open a prompt and say what to observe. An agent runs it on the side
and returns control to the editor: a result table for a query, or a stopped
nvim-dap session for a breakpoint. RunMe never edits source files.

## Usage

| Key / command | Action |
| --- | --- |
| `<leader>hr` (n) | Prompt with the cursor context |
| `<leader>hr` (x), `:'<,'>RunMe` | The selection is the subject |
| `:RunMe [text]` | Start immediately (`? ` query, `! ` break, `> ` observe) |
| `:RunMeResume` | Reopen the panel (or restore the last run from history) |
| `:RunMeHistory` | Pick a past run; `i` in the panel continues its pi session |
| `:RunMeCancel` | Cancel and clean up the debugger |

Prompt float: the title shows the mode and target, the footer shows the detected subject.
`<Tab>` cycles the mode (`auto`/`query`/`break`/`observe`), `<C-t>` toggles the target
`local` ↔ `prod`, `<Esc>`/`<C-c>` closes. A detected query preselects `query`.

Panel (right split, `runme://panel`, the run continues when you close it):

| Key | Action |
| --- | --- |
| `a` / `n` | Approve / decline the pending command |
| `i` | Follow-up in the same pi session |
| `r` | Re-run the prompt as a new run |
| `e` | Edit the result's query in a scratch buffer; `:w` re-runs it |
| `o` | Open the full result table in a split |
| `y` | Yank the result |
| `gd` | Jump to the stop location (or the source line) |
| `d` | Toggle dap-ui |
| `x` | Cancel (abort pi, remove RunMe breakpoints; before handoff also resume + detach) |
| `q` | Close the panel |

## Files

| Path | Role |
| --- | --- |
| `lua/config/runme/init.lua` | Setup, prompt float, run lifecycle, RPC event handling, approvals, history |
| `lua/config/runme/context.lua` | Context capture: treesitter symbol, query detection, project profile, DAP state |
| `lua/config/runme/session.lua` | `pi --mode rpc` process and LF-only JSONL framing |
| `lua/config/runme/bridge.lua` | Debugger operations on the user's nvim-dap, with RunMe-owned breakpoint tracking and cleanup |
| `lua/config/runme/panel.lua` | Panel rendering and result tables |
| `pi/runme.ts` | pi extension: `runme_*` tools, bash guard, prod SQL runner |
| `pi/runme-policy.ts` | Pure safety rules (deny list, read-only detection, prod SQL preparation) |
| `tests/runme.lua` | Headless tests, including a scripted fake pi over the real RPC pipe |
| `pi/runme-policy.test.ts` | `node --test pi/runme-policy.test.ts` |

Wired in `lua/config/keymaps.lua` with `require('config.runme').setup()`.

## Architecture

```
nvim                                                pi --mode rpc (cwd = project root)
 init.lua ── prompt / follow_up / abort ──────────►  -e pi/runme.ts
          ◄── events (JSONL): tool starts/ends,      -e pi-config tmux, mysql-dev (phonetrac)
              text deltas, agent_end                 --skill ctm-mysql, ctm-query-review, ctm-elasticsearch,
          ◄── extension_ui_request ───────────────      ctm-redis, synthetic-user, phonetrac-patterns
              confirm  → panel approval (a/n)        --exclude-tools edit,write,dap_*
              input "runme:bridge" → bridge.lua
          ── extension_ui_response ───────────────►
```

- **Bridge transport.** Debugger tools use pi's extension UI sub-protocol: the tool
  calls `ctx.ui.input("runme:bridge", <json request>)`, nvim runs the operation and replies
  with the JSON result. This needs no socket, keeps one pipe, and lets long waits
  (`runme_wait_stopped`) complete asynchronously without blocking the editor.
- **Display tools** (`runme_plan`, `runme_step`, `runme_result`) are no-ops in pi; the panel
  renders them from the `tool_execution_start` event arguments.
- **One DAP client.** rdbg accepts one client, so pi-config's `dap_*` tools are excluded
  and the agent works through the user's nvim-dap session.

### Tools (`pi/runme.ts`)

| Tool | Effect |
| --- | --- |
| `runme_plan {steps}` / `runme_step {index, status, note}` | Plan section |
| `runme_result {title, text?, columns?, rows?, query?, language?, target?}` | Result section |
| `runme_context` | Re-capture editor context |
| `runme_dap_status` | Session, port, stopped frame, breakpoints |
| `runme_dap_attach {target: rails\|worker\|port}` | Runs the matching `dap/ruby.lua` attach config (38698 / 38699); idempotent |
| `runme_breakpoint {file, line, condition?, hit_condition?, log_message?}` | Sets a breakpoint owned by RunMe |
| `runme_breakpoint_clear` | Removes only RunMe-owned breakpoints |
| `runme_wait_stopped {timeout_s}` | Resolves on `event_stopped` with file/line/thread |
| `runme_dap_eval {expression}` | Evaluates in the stopped frame |
| `runme_handoff {message}` | Opens dap-ui, focuses the frame, ends the agent turn |
| `runme_prod_sql {sql, purpose, limit?}` | Production read (see Safety) |

## Modes

- **query**: for ActiveRecord the agent builds the exact SQL with `rails runner '... .to_sql'`,
  runs it locally with `mysql_dev` (SELECT-only grants), or on prod with `runme_prod_sql`.
- **break**: attach (rails for request code, worker for jobs) → conditional breakpoint →
  background trigger (curl, `rails runner`, synthetic-user) → wait → optional eval → handoff.
- **observe**: local `rails runner` inside a rolled-back transaction with
  `sql.active_record` capture; other projects use the narrowest test/command. Never in prod.

## Safety

| Layer | Rule |
| --- | --- |
| Tools | `edit`, `write`, `dap_*` excluded; bridge ops are a fixed handler table |
| Bash guard | Deny: tmux kill/`set -s`, `ctmstart`/`ctmstop`, kill, `rm`, git writes, `ssh`/`scp`, `RAILS_ENV=production`, `mysql` CLI, destructive `db:` tasks, docker teardown, redis writes |
| Local approval | Non-read-only bash needs `a` in the panel unless `approve_local = true` |
| Prod | Only `runme_prod_sql`: one SELECT/WITH, no locking reads or `INTO`, `MAX_EXECUTION_TIME(3000)` hint + session limit, forced `LIMIT`, `EXPLAIN` first, refused above `prod_row_ceiling` estimated rows in one table, then explicit approval. Runs through `ssh reader` + `bin/query --no-print` per the `ctm-mysql` skill |
| Debugger | Conditional breakpoints preferred; RunMe-owned breakpoints are removed on cancel, pi exit, new run, and `VimLeavePre`. Before handoff, cancel also resumes a suspended thread and detaches a session RunMe attached |
| Timeouts | `run_timeout` cancels a busy agent with cleanup; an idle one only loses its pi process (a follow-up resumes the session id) |
| Audit | Each run is recorded in `stdpath('data')/runme_history.json`; pi sessions live in `stdpath('data')/runme/sessions` |

## Config

```lua
require('config.runme').setup {
  keymap = '<leader>hr',
  pi = { executable = stdpath('config') .. '/bin/pi-mise', model = 'openai-codex/gpt-6.1-sol', thinking = 'medium', mcp = true },
  pi_config_dir = '~/peter-projects/pi-config',
  approve_local = false,
  prod_row_ceiling = 1000000,
  run_timeout = 1800,
  history_limit = 100,
}
```

## Decisions on the open questions

1. Web triggers: no stored cookie; the agent uses what the code allows (basic auth in source,
   `rails runner`, synthetic-user) or asks you to trigger.
2. The agent may `runme_dap_eval` in your session before handoff, never after.
3. Prod: MySQL through `runme_prod_sql`. ES/Redis prod reads are not exposed yet.
4. Model: Codex (`openai-codex/gpt-6.1-sol`), pinned in config, `thinking = 'medium'`.
5. Location: this config, with the pi extension in `pi/` so both sides version together.

## Verification (2026-11-13)

- `tests/runme.lua`: 6 groups (context detection, prefixes, rendering, bridge with real
  nvim-dap breakpoints, debugger cleanup, end-to-end over the RPC pipe with a fake pi).
- `pi/runme-policy.test.ts`: deny list, read-only detection, prod SQL preparation.
- Live against the local stack: query mode on `Account#publish_tracking_rules` (45 s, one
  approval), break mode on `HealthController#show` (attach 38698 → conditional breakpoint →
  background curl → stop → eval → handoff, 33 s), prod-reader `SELECT id FROM accounts`
  (EXPLAIN → approval → result).

## Not yet done

- Prod ES/Redis reads (`ctm-elasticsearch`/`ctm-redis` patterns as typed tools).
- Bookmark export of a run ("save as bookmark-walk stop").
