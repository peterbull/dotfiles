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
| `a` / `n` | Approve / decline a pending production query |
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
| `pi/runme-triggers.ts` | Trigger runners (HTTP, CDP browser, command, synthetic-user), Rails log cursor, Ruby executable-line check |
| `tests/runme.lua` | Headless tests, including a scripted fake pi over the real RPC pipe |
| `pi/runme-*.test.ts` | `node --test pi/runme-policy.test.ts pi/runme-triggers.test.ts` |

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
| `runme_dap_continue {reason}` | Resumes a stop that is not RunMe's (before handoff only) |
| `runme_handoff {message}` | Opens dap-ui, focuses the frame, ends the agent turn |
| `runme_trigger_browser {url, script?}` | Opens a local URL in a background tab of the logged-in agent Chrome (9223), or runs `script` (e.g. `fetch`) in an app page so the session and CSRF token apply |
| `runme_trigger_http {method, url, headers?, body?, basic_auth?, browser_session?}` | One background request to the local stack; `browser_session` sends the agent Chrome's cookies |
| `runme_trigger_command {command}` | Background shell command, e.g. `rails runner 'Resque.enqueue(...)'` for the debugged worker |
| `runme_trigger_call {call? \| scenarioPath?}` | Simulated customer call through the local synthetic-user MCP server (127.0.0.1:7391) |
| `runme_trigger_status {trigger_id}` | State, HTTP/document status, redirect, output, call status, and Rails log lines since the trigger |
| `runme_prod_sql {sql, purpose, limit?}` | Production read (see Safety) |

## Modes

- **query**: for ActiveRecord the agent builds the exact SQL with `rails runner '... .to_sql'`,
  runs it locally with `mysql_dev` (SELECT-only grants), or on prod with `runme_prod_sql`.
- **break**: place → choose process → find the entry point → trigger → verify → hand off.
  - *Place*: `runme_breakpoint` checks the line against Ruby's own line table
    (`RubyVM::InstructionSequence#trace_points`), because rdbg reports every breakpoint in a
    locatable file as verified. A non-executable line returns `will_stop: false` and the
    nearest executable lines, and the agent moves it.
  - *Process*: request code → rails (38698); jobs → worker (38699) and must be enqueued,
    because `perform_now` in `rails runner` runs outside the debugger. If another client
    already holds the rdbg port, attach fails at once and names the holder's pid.
  - *Trigger*: browser for pages and frontend XHR/GraphQL, HTTP for API/webhooks, command
    for jobs, synthetic-user for call flows. All triggers run in the background (a held
    breakpoint blocks the request; rails runs single-threaded under the debugger) and
    reach only hosts that resolve to loopback.
  - *Verify*: `runme_wait_stopped` reports `hit` = `runme` / `user` / `other`. `runme` is
    confirmed with an eval that proves it is the intended request. On a timeout,
    `runme_trigger_status` reads the status code, redirect, and the Rails log since the trigger:
    no `Started` line means it never reached the process; a different `Processing by` means the
    wrong route; 401, a sign-in redirect, or `Filter chain halted` means auth; the right action
    completing without a stop means the branch was not taken or the condition was false (retry
    without the condition). At most two retries, each with a stated hypothesis.
  - *Hand off* only after a verified `runme` stop.
- **observe**: local `rails runner` inside a rolled-back transaction with
  `sql.active_record` capture; other projects use the narrowest test/command. Never in prod.

## Safety

| Layer | Rule |
| --- | --- |
| Tools | `edit`, `write`, `dap_*` excluded; bridge ops are a fixed handler table |
| Bash guard | Deny: tmux kill/`set -s`, `ctmstart`/`ctmstop`, kill, `rm`, git writes, `ssh`/`scp`, `RAILS_ENV=production`, `mysql` CLI, destructive `db:` tasks, docker teardown, redis writes |
| Approval | Only production: `runme_prod_sql` waits for `a`/`n` in the panel. Local commands and triggers run without prompts; the deny list still applies |
| Triggers | Loopback hosts only (DNS must resolve to 127.0.0.0/8 or ::1). The synthetic-user token is read by the extension from Claude Code's MCP config (or `RUNME_SYNTHETIC_TOKEN`) and never reaches the model. Background commands are killed on pi shutdown |
| Prod | Only `runme_prod_sql`: one SELECT/WITH, no locking reads or `INTO`, `MAX_EXECUTION_TIME(3000)` hint + session limit, forced `LIMIT`, `EXPLAIN` first, refused above `prod_row_ceiling` estimated rows in one table, then explicit approval. Runs through `ssh reader` + `bin/query --no-print` per the `ctm-mysql` skill |
| Debugger | Conditional breakpoints preferred; RunMe-owned breakpoints are removed on cancel, pi exit, new run, and `VimLeavePre`. Before handoff, cancel also resumes a suspended thread and detaches a session RunMe attached |
| Timeouts | `run_timeout` cancels a busy agent with cleanup; an idle one only loses its pi process (a follow-up resumes the session id) |
| Audit | Each run is recorded in `stdpath('data')/runme_history.json`; pi sessions live in `stdpath('data')/runme/sessions` |

## Config

```lua
require('config.runme').setup {
  keymap = '<leader>hr',
  pi = { executable = stdpath('config') .. '/bin/pi-mise', model = 'openai-codex/gpt-6.1-sol', thinking = 'medium' },
  pi_config_dir = '~/peter-projects/pi-config',
  prod_row_ceiling = 1000000,
  run_timeout = 1800,
  history_limit = 100,
}
```

## Decisions on the open questions

1. Triggers: the agent triggers the code itself (browser with the agent Chrome's login, HTTP with
   API keys or the browser's cookies, enqueued jobs, synthetic-user calls) and proves the stop.
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

Trigger and verification runs (2026-11-13, against a private rdbg rails on :3457/:38710
because the user's own nvim held :38698):

- Held port: attach to :38698 failed in 56 ms and named the holder (`nvim pid …`).
- API (`Api::V1::AccountsController#show`, account 4): moved 531 → 532, triggered over HTTP,
  proved a 401 from status and log, found no local API keys, reported the block, and cleaned up.
- Browser (`PagesController#affiliates`): the page load was redirected by `ensure_www`; the agent
  found it through trigger status, retried, stopped with `hit: runme`, confirmed the path with an
  eval, and handed off.
- Branch not taken (`PagesController#canceled`): a signed-out request redirects before the
  line; the agent proved entry with a breakpoint at the first statement and `signed_in: false`.

## Not yet done

- Live check of a worker (`Resque.enqueue`) trigger and a synthetic-user call trigger.

- Prod ES/Redis reads (`ctm-elasticsearch`/`ctm-redis` patterns as typed tools).
- Bookmark export of a run ("save as bookmark-walk stop").
