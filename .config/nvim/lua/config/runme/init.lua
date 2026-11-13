local Bridge = require 'config.runme.bridge'
local Context = require 'config.runme.context'
local Panel = require 'config.runme.panel'
local Session = require 'config.runme.session'

local M = {}

---@alias runme.Mode 'auto'|'query'|'break'|'observe'
---@alias runme.Target 'local'|'prod'

M.MODES = { 'auto', 'query', 'break', 'observe' } ---@type runme.Mode[]
local PREFIX_MODE = { ['?'] = 'query', ['!'] = 'break', ['>'] = 'observe' }

---@class runme.Config
M.config = {
  keymap = '<leader>hr',
  pi = {
    executable = vim.fn.stdpath 'config' .. '/bin/pi-mise',
    model = 'openai-codex/gpt-6.1-sol', ---@type string|nil
    thinking = 'medium', ---@type string|nil
  },
  pi_config_dir = vim.fn.expand '~/peter-projects/pi-config',
  extension = vim.fn.stdpath 'config' .. '/pi/runme.ts',
  session_dir = vim.fn.stdpath 'data' .. '/runme/sessions',
  history_file = vim.fn.stdpath 'data' .. '/runme_history.json',
  history_limit = 100,
  prod_row_ceiling = 1000000,
  run_timeout = 1800,
}

local SYSTEM_PROMPT = [[
You are RunMe, an execution assistant embedded in the user's Neovim. The user points at code and asks you to run it, observe it, query data, or stop in it with the debugger. You never edit files.

Workflow:
1. Call runme_plan first with 2-6 short steps, then keep them current with runme_step.
2. Do the work with as few tool calls as possible. Keep output small (LIMIT, head, targeted reads).
3. Finish with runme_result (or runme_handoff in break mode), then at most three sentences of findings.

Modes (the request states one; `auto` means choose the best fit):
- query: run the detected query or an analog. For ActiveRecord in the phonetrac profile, build the exact SQL locally with `mise exec -- bundle exec rails runner 'puts <relation>.to_sql'`. Local target: run the SQL with mysql_dev. Prod target: run it only with runme_prod_sql. Bind values from the request; if none are given, pick a realistic sample and say which. Report with runme_result including columns, rows, and the exact query.
- break: stop the debugger where the user points, trigger that code yourself, prove the stop is the intended one, then hand off. Follow the break playbook below.
- observe: run the code locally and report output, return values, and executed SQL. In the phonetrac profile use `mise exec -- bundle exec rails runner` with the script wrapped in `ActiveRecord::Base.transaction do ... raise ActiveRecord::Rollback end` unless the user says to commit, and subscribe to `sql.active_record` to list executed SQL. In other projects run the narrowest test or command for the filetype. Observe never runs in prod.

Break playbook:
1. Place. Break on the cursor line unless the request names another place. runme_breakpoint reports `will_stop`; when it is false, move the breakpoint to the suggested executable line before doing anything else. Add a `condition` that narrows to the entity the user named; leave it out when no safe expression exists.
2. Choose the process. Request-handling code (controllers, GraphQL, webhooks, and models or services they call) runs in rails: runme_dap_attach target=rails. Resque jobs (app/jobs, `perform`) run in the debugged worker: target=worker, and the job must be enqueued (`Resque.enqueue` / `perform_later`) so that worker runs it. `perform_now` inside `rails runner` runs in the runner process, which has no debugger.
3. Find the real entry point. Read config/routes.rb or the controller, GraphQL type, or job to learn the URL, HTTP method, params, and auth the code path needs.
4. Trigger it yourself with the closest real entry point:
   - A page, or code reached from a page load: runme_trigger_browser with the local app URL (https://app.ctmdev.us/...). The agent Chrome is logged in.
   - An XHR, JSON, or GraphQL call that the app's frontend makes: runme_trigger_browser with `script` that calls fetch() from an app page, so the session cookie and CSRF token apply (read the token from `document.querySelector('meta[name=csrf-token]')`).
   - An API endpoint, webhook, or health check: runme_trigger_http. API keys use basic_auth (find a local account's key with mysql_dev); session-authenticated endpoints can use browser_session=true.
   - A job, rake task, or runner path: runme_trigger_command.
   - Call routing, IVR, VoiceAI, or Twilio webhooks: runme_trigger_call.
   Make the trigger match the breakpoint condition (same account, record, or params).
5. Verify. A trigger is not done until you know what it did:
   a. Call runme_wait_stopped right after the trigger: 30-60 s for browser and HTTP triggers, longer for jobs and calls.
   b. On a stop, check `hit`. `runme` means your breakpoint fired: confirm it is the intended request with runme_dap_eval (the condition, params, ids, current user or account). `user` or `other` (another breakpoint, an exception) means it stopped elsewhere: report where, and use runme_dap_continue only when the stop is unrelated and your breakpoint is still ahead.
   c. On a timeout, call runme_trigger_status and read the status code, the redirect location, and `rails_log_since_trigger`:
      - No `Started` line: the request never reached the debugged process (wrong host or port, a browser error, a job not enqueued, or the wrong worker).
      - `Processing by` a different Controller#action: wrong route; fix the URL or method.
      - 401, a redirect to sign-in, `Filter chain halted`, or a CSRF error: an auth problem; switch to the browser session or supply credentials.
      - The right action, `Completed 2xx`, and no stop: the line was not reached (a branch not taken) or the condition was false. Retry once without the condition, or with a breakpoint at the first line of the action, to prove entry.
      - Still pending with no completion: something else holds it (check runme_dap_status).
   d. Retry at most twice. State the hypothesis each retry tests. If it still does not stop, report what you proved, clear your breakpoints with runme_breakpoint_clear, and stop.
6. Hand off only after a verified `runme` stop. Call runme_handoff with where it stopped, which trigger caused it, and the key values. Never continue, step, or detach after handoff. The triggering request stays held until the user continues.

Rules:
- Target prod allows only runme_prod_sql. Nothing else touches production.
- Ruby and Rails commands run through `mise exec -- bundle exec`, never rvm.
- If a dev service you need is down (tmux session ctm-server, windows rails and resque-debug), say so and stop. Never start or stop services.
- Trigger with the runme_trigger_* tools, not bash: they run in the background, stay on the local stack, and record what happened.
- rdbg accepts one debugger client: use only the runme_* debugger tools.
]]

local state = {
  run = nil, ---@type runme.Run|nil
  session = nil, ---@type runme.Session|nil
  context = nil, ---@type runme.Context|nil
  streaming = false,
  render_timer = nil, ---@type uv.uv_timer_t|nil
  run_timer = nil, ---@type uv.uv_timer_t|nil
  tool_log = {}, ---@type table<string, integer>
}
M._state = state

---@return string
local function new_id()
  return string.format('runme-%s-%04x', os.date '%Y%m%d-%H%M%S', math.random(0, 0xffff))
end

---@param path string
---@return boolean
local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

---@return table[]
function M.load_history()
  local f = io.open(M.config.history_file, 'r')
  if not f then
    return {}
  end
  local content = f:read '*a'
  f:close()
  local ok, data = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if ok and type(data) == 'table' then
    return data
  end
  vim.notify('RunMe: history file is unreadable: ' .. M.config.history_file, vim.log.levels.WARN)
  return {}
end

---@param history table[]
local function save_history(history)
  local f, err = io.open(M.config.history_file, 'w')
  if not f then
    vim.notify('RunMe: cannot write history: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end
  f:write(vim.json.encode(history))
  f:close()
end

---@param run runme.Run
local function record_history(run)
  local history = vim.tbl_filter(function(entry)
    return entry.id ~= run.id
  end, M.load_history())
  table.insert(history, 1, {
    id = run.id,
    timestamp = run.started,
    finished = run.finished,
    prompt = run.prompt,
    mode = run.mode,
    target = run.target,
    file = run.file,
    line = run.line,
    status = run.status,
    notes = run.notes,
    result = run.result,
    plan = run.plan,
  })
  save_history(vim.list_slice(history, 1, M.config.history_limit))
end

local function render_now()
  if state.run then
    Panel.render(state.run)
  end
end

local function render()
  if state.render_timer then
    return
  end
  state.render_timer = vim.defer_fn(function()
    state.render_timer = nil
    render_now()
  end, 40)
end

---@param text string
---@param log_state 'running'|'ok'|'error'|'info'
---@param id? string
local function log(text, log_state, id)
  local run = state.run
  if not run then
    return
  end
  table.insert(run.log, { id = id, text = text, state = log_state })
  if id then
    state.tool_log[id] = #run.log
  end
  render()
end

---@param value any
---@param max integer
---@return string
local function brief(value, max)
  local text = type(value) == 'string' and value or vim.json.encode(value)
  text = text:gsub('%s+', ' ')
  if #text > max then
    return text:sub(1, max - 1) .. '…'
  end
  return text
end

---@param ctx runme.Context
---@return string[]
function M.build_cmd(ctx, session_id)
  local cfg = M.config
  local cmd = {
    cfg.pi.executable,
    '--mode',
    'rpc',
    '--session-dir',
    cfg.session_dir,
    '--session-id',
    session_id,
    '--no-extensions',
    '--no-skills',
    '--no-prompt-templates',
    '--no-themes',
    '--exclude-tools',
    'edit,write,dap_*',
    '--append-system-prompt',
    SYSTEM_PROMPT,
    '-e',
    cfg.extension,
  }
  if cfg.pi.model then
    vim.list_extend(cmd, { '--model', cfg.pi.model })
  end
  if cfg.pi.thinking then
    vim.list_extend(cmd, { '--thinking', cfg.pi.thinking })
  end
  local pc = cfg.pi_config_dir
  for _, ext in ipairs { '/extensions/tmux/index.ts', '/extensions/mysql-dev.ts' } do
    if exists(pc .. ext) and (ctx.project == 'phonetrac' or ext:find 'tmux') then
      vim.list_extend(cmd, { '-e', pc .. ext })
    end
  end
  if ctx.project == 'phonetrac' then
    for _, skill in ipairs { 'ctm-mysql', 'ctm-query-review', 'ctm-elasticsearch', 'ctm-redis', 'phonetrac-patterns' } do
      local path = pc .. '/skills/' .. skill
      if exists(path .. '/SKILL.md') then
        vim.list_extend(cmd, { '--skill', path })
      end
    end
  end
  return cmd
end

---@param run runme.Run
---@param ctx runme.Context
---@return string
function M.build_message(run, ctx)
  return table.concat({
    'Mode: ' .. run.mode,
    'Target: ' .. run.target .. (run.target == 'prod' and ' (production reader, read-only, runme_prod_sql only)' or ' (local dev)'),
    '',
    ctx.text,
    '',
    'Request: ' .. run.prompt,
  }, '\n')
end

---@param request table
local function handle_ui_request(request)
  local session = state.session
  if not session then
    return
  end
  local method = request.method
  if method == 'input' and request.title == 'runme:bridge' then
    local ok, payload = pcall(vim.json.decode, request.placeholder or '', { luanil = { object = true, array = true } })
    if not ok then
      session:send { type = 'extension_ui_response', id = request.id, value = vim.json.encode { ok = false, error = 'bad bridge payload' } }
      return
    end
    Bridge.handle(payload, function(success, result)
      if not session.alive then
        return
      end
      session:send {
        type = 'extension_ui_response',
        id = request.id,
        value = vim.json.encode { ok = success, result = success and result or nil, error = (not success) and tostring(result) or nil },
      }
    end)
  elseif method == 'confirm' and state.run then
    state.run.approval = { id = request.id, title = request.title or 'Approve?', message = request.message or '' }
    state.run.status = 'awaiting approval'
    Panel.open(false)
    render_now()
    vim.notify('RunMe: approval needed — ' .. (request.title or ''), vim.log.levels.WARN)
  elseif method == 'select' then
    vim.ui.select(request.options or {}, { prompt = request.title }, function(choice)
      session:send { type = 'extension_ui_response', id = request.id, value = choice, cancelled = choice == nil or nil }
    end)
  elseif method == 'input' or method == 'editor' then
    vim.ui.input({ prompt = (request.title or 'Input') .. ': ', default = request.prefill }, function(value)
      session:send { type = 'extension_ui_response', id = request.id, value = value, cancelled = value == nil or nil }
    end)
  elseif method == 'notify' then
    vim.notify('RunMe: ' .. (request.message or ''), request.notifyType == 'error' and vim.log.levels.ERROR or vim.log.levels.INFO)
  end
end

---@param run runme.Run
---@param name string
---@param args table
local function apply_tool_start(run, name, args)
  if name == 'runme_plan' then
    run.plan = vim.tbl_map(function(text)
      return { text = text, status = 'pending' }
    end, args.steps or {})
  elseif name == 'runme_step' then
    local step = run.plan[args.index]
    if step then
      step.status = args.status
      step.note = args.note
    end
  elseif name == 'runme_result' then
    run.result = {
      title = args.title or 'Result',
      text = args.text,
      columns = args.columns,
      rows = args.rows,
      query = args.query,
      language = args.language,
      target = args.target or run.target,
    }
  end
end

local QUIET_TOOLS = { runme_plan = true, runme_step = true, runme_result = true }

---@param msg table
local function on_message(msg)
  local run = state.run
  if not run then
    return
  end
  local kind = msg.type
  if kind == 'agent_start' then
    state.streaming = true
    run.status = 'running'
    run.finished = nil
  elseif kind == 'agent_end' then
    state.streaming = false
    if run.status ~= 'handed off' and run.status ~= 'cancelled' then
      run.status = 'idle'
    end
    run.finished = os.time()
    record_history(run)
  elseif kind == 'message_update' then
    local event = msg.assistantMessageEvent or {}
    if event.type == 'text_delta' then
      run.streaming = run.streaming .. (event.delta or '')
    end
  elseif kind == 'message_end' then
    local message = msg.message or {}
    if message.role == 'assistant' then
      if vim.trim(run.streaming) ~= '' then
        table.insert(run.notes, vim.trim(run.streaming))
      end
      run.streaming = ''
      if message.stopReason == 'error' and message.errorMessage then
        log('model error: ' .. message.errorMessage, 'error')
      end
    end
  elseif kind == 'tool_execution_start' then
    apply_tool_start(run, msg.toolName, msg.args or {})
    if not QUIET_TOOLS[msg.toolName] then
      log(string.format('%s %s', msg.toolName, brief(msg.args or {}, 160)), 'running', msg.toolCallId)
    end
  elseif kind == 'tool_execution_end' then
    local index = state.tool_log[msg.toolCallId]
    local entry = index and run.log[index]
    local content = msg.result and msg.result.content or {}
    local text = content[1] and content[1].text or ''
    if entry then
      entry.state = msg.isError and 'error' or 'ok'
      entry.text = entry.text .. '  → ' .. brief(text, msg.isError and 400 or 120)
    end
    if msg.toolName == 'runme_prod_sql' and not msg.isError then
      local details = msg.result.details or {}
      if details.columns then
        run.result = { title = 'prod reader', columns = details.columns, rows = details.rows, query = details.sql, language = 'sql', target = 'prod' }
      end
    end
  elseif kind == 'extension_ui_request' then
    handle_ui_request(msg)
  elseif kind == 'extension_error' then
    log(string.format('extension error (%s): %s', msg.event or '?', msg.error or ''), 'error')
  elseif kind == 'response' and msg.success == false then
    log(string.format('%s failed: %s', msg.command or 'command', msg.error or ''), 'error')
  elseif kind == 'auto_retry_start' then
    log('retrying after transient error', 'info')
  elseif kind == 'runme_stream_error' then
    log(msg.error, 'error')
  end
  render()
end

local function stop_run_timer()
  if state.run_timer then
    state.run_timer:stop()
    if not state.run_timer:is_closing() then
      state.run_timer:close()
    end
    state.run_timer = nil
  end
end

---@param reason string
function M.cancel(reason)
  local run = state.run
  stop_run_timer()
  local actions = Bridge.cleanup()
  if state.session then
    state.session:abort()
    state.session:stop()
    state.session = nil
  end
  if run then
    run.approval = nil
    run.status = 'cancelled'
    run.finished = run.finished or os.time()
    log(reason .. (#actions > 0 and (': ' .. table.concat(actions, ', ')) or ''), 'info')
    record_history(run)
    render_now()
  end
end

---@param ctx runme.Context
---@param run runme.Run
local function spawn(ctx, run)
  vim.fn.mkdir(M.config.session_dir, 'p')
  state.tool_log = {}
  Bridge.reset {
    root = ctx.root,
    source_win = vim.api.nvim_get_current_win(),
    on_handoff = function(message, frame)
      run.status = 'handed off'
      if frame then
        run.stop = frame
      end
      table.insert(run.notes, message)
      render()
      vim.notify('RunMe: ' .. message, vim.log.levels.INFO)
    end,
  }
  local session
  session = Session.start {
    id = run.id,
    cmd = M.build_cmd(ctx, run.id),
    cwd = ctx.root,
    env = {
      RUNME_PROD_ROW_CEILING = tostring(M.config.prod_row_ceiling),
    },
    on_message = function(msg)
      if state.session == session then
        on_message(msg)
      end
    end,
    on_exit = function(code, stderr)
      if state.session ~= session then
        return
      end
      state.session = nil
      state.streaming = false
      stop_run_timer()
      if run.status ~= 'cancelled' then
        run.status = code == 0 and 'exited' or 'error'
        if code ~= 0 then
          log(string.format('pi exited %d: %s', code, brief(stderr, 600)), 'error')
        end
        Bridge.cleanup()
      end
      render_now()
    end,
  }
  state.session = session
  return session
end

-- A busy agent past the limit is cancelled with full cleanup; an idle one only
-- loses its pi process, and a follow-up resumes the same session id.
local function arm_run_timer()
  stop_run_timer()
  local session = state.session
  state.run_timer = vim.defer_fn(function()
    state.run_timer = nil
    if state.session ~= session or not session then
      return
    end
    if state.streaming then
      M.cancel(string.format('timed out after %ds', M.config.run_timeout))
    else
      state.session = nil
      session:stop()
    end
  end, M.config.run_timeout * 1000)
end

---@param prompt string
---@param mode runme.Mode
---@param target runme.Target
---@param ctx runme.Context
function M.start(prompt, mode, target, ctx)
  if state.session then
    M.cancel 'replaced by a new run'
  end
  ---@type runme.Run
  local run = {
    id = new_id(),
    prompt = prompt,
    mode = mode,
    target = target,
    file = ctx.file,
    line = ctx.cursor_line,
    status = 'starting',
    started = os.time(),
    plan = {},
    log = {},
    notes = {},
    streaming = '',
  }
  state.run = run
  state.context = ctx
  local session = spawn(ctx, run)
  session:prompt(M.build_message(run, ctx), false)
  arm_run_timer()
  Panel.open(false)
  render_now()
end

---@param text string
function M.follow_up(text)
  local run = state.run
  if not run then
    vim.notify('RunMe: no run to follow up', vim.log.levels.WARN)
    return
  end
  if not state.session then
    if not state.context then
      vim.notify('RunMe: no session to resume', vim.log.levels.WARN)
      return
    end
    spawn(state.context, run)
  end
  run.status = 'running'
  table.insert(run.notes, '› ' .. text)
  state.session:prompt(text, state.streaming)
  arm_run_timer()
  render_now()
end

---@param approved boolean
function M.answer_approval(approved)
  local run = state.run
  if not (run and run.approval and state.session) then
    return
  end
  state.session:send { type = 'extension_ui_response', id = run.approval.id, confirmed = approved }
  log((approved and 'approved: ' or 'declined: ') .. run.approval.title, 'info')
  run.approval = nil
  run.status = 'running'
  render_now()
end

local function edit_query()
  local result = state.run and state.run.result
  if not (result and result.query) then
    vim.notify('RunMe: the result has no query to edit', vim.log.levels.INFO)
    return
  end
  local language = result.language or 'sql'
  vim.cmd 'botright new'
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, string.format('runme://query-%d.%s', buf, language == 'ruby' and 'rb' or language))
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = language
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result.query, '\n', { plain = true }))
  vim.bo[buf].modified = false
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local query = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      vim.bo[buf].modified = false
      M.follow_up(
        string.format(
          'Re-run this edited %s on target %s exactly as written (apply the same safety rules), then show it with runme_result:\n```%s\n%s\n```',
          language,
          result.target or state.run.target,
          language,
          query
        )
      )
    end,
  })
end

local function jump()
  local run = state.run
  if not run then
    return
  end
  local file, line = run.file, run.line
  if run.stop and run.stop.file then
    file, line = run.stop.file, run.stop.line
  end
  local source = Bridge.state.source_win
  if source and vim.api.nvim_win_is_valid(source) then
    vim.api.nvim_set_current_win(source)
  else
    vim.cmd 'wincmd p'
  end
  vim.cmd.edit(vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
end

local HELP = {
  'a  approve pending command      n  decline',
  'i  follow-up in same session    r  re-run prompt',
  'e  edit query, :w re-runs       o  open full result',
  'y  yank result                  gd jump to stop/source',
  'd  toggle dap-ui                x  cancel (cleans up debugger)',
  'q  close panel (run continues)',
}

local function map_panel(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = 'RunMe: ' .. desc })
  end
  map('a', function()
    M.answer_approval(true)
  end, 'approve')
  map('n', function()
    M.answer_approval(false)
  end, 'decline')
  map('x', function()
    M.cancel 'cancelled by user'
  end, 'cancel')
  map('q', Panel.close, 'close panel')
  map('i', function()
    vim.ui.input({ prompt = 'RunMe follow-up: ' }, function(text)
      if text and vim.trim(text) ~= '' then
        M.follow_up(vim.trim(text))
      end
    end)
  end, 'follow-up')
  map('r', function()
    local run, ctx = state.run, state.context
    if run and ctx then
      M.start(run.prompt, run.mode, run.target, ctx)
    end
  end, 're-run')
  map('e', edit_query, 'edit query')
  map('o', function()
    if state.run and state.run.result then
      Panel.open_result(state.run.result)
    end
  end, 'open result')
  map('y', function()
    local result = state.run and state.run.result
    if not result then
      return
    end
    local text = result.text or ''
    if result.columns and result.rows then
      text = table.concat(Panel.table_lines(result.columns, result.rows, nil, 200), '\n')
    end
    vim.fn.setreg('+', text)
    vim.notify('RunMe: result yanked', vim.log.levels.INFO)
  end, 'yank result')
  map('gd', jump, 'jump')
  map('d', function()
    local ok, dapui = pcall(require, 'dapui')
    if ok then
      dapui.toggle {}
    end
  end, 'toggle dap-ui')
  map('?', function()
    vim.notify(table.concat(HELP, '\n'), vim.log.levels.INFO, { title = 'RunMe' })
  end, 'help')
end

---@param input string
---@param mode runme.Mode
---@return string prompt, runme.Mode mode
function M.parse_prefix(input, mode)
  local first = input:sub(1, 1)
  if PREFIX_MODE[first] then
    return vim.trim(input:sub(2)), PREFIX_MODE[first]
  end
  return input, mode
end

---@param ctx runme.Context
---@return string
local function subject_label(ctx)
  local name = vim.fn.fnamemodify(ctx.file, ':t')
  if ctx.query then
    local first = vim.trim(vim.split(ctx.query.text, '\n')[1]):sub(1, 40)
    return string.format(' %s: %s  %s:%d ', ctx.query.kind, first, name, ctx.query.start_line)
  end
  if ctx.symbol then
    return string.format(' %s  %s:%d ', ctx.symbol.path, name, ctx.cursor_line)
  end
  return string.format(' %s:%d ', name, ctx.cursor_line)
end

local FOOTER_HINT = ' <Tab> mode · <C-t> target '

---@param ctx runme.Context
---@param width integer
---@return table
local function footer(ctx, width)
  local label = subject_label(ctx)
  local room = width - vim.fn.strdisplaywidth(FOOTER_HINT) - 4
  if vim.fn.strdisplaywidth(label) > room then
    label = vim.fn.strcharpart(label, 0, math.max(0, room - 2)) .. '… '
  end
  return { { label, 'Comment' }, { FOOTER_HINT, 'NonText' } }
end

---@param opts? { selection?: { start_line: integer, end_line: integer }, text?: string }
function M.show(opts)
  opts = opts or {}
  local ctx = Context.capture { selection = opts.selection }
  local mode = (ctx.query and 'query' or 'auto') --[[@as runme.Mode]]
  local target = 'local' --[[@as runme.Target]]

  if opts.text and opts.text ~= '' then
    local prompt, parsed = M.parse_prefix(opts.text, mode)
    M.start(prompt, parsed, target, ctx)
    return
  end

  local width = math.floor(math.min(vim.o.columns * 0.6, 90))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'prompt'
  vim.bo[buf].bufhidden = 'wipe'
  vim.b[buf].completion = false

  local function title()
    return {
      { ' RunMe ', 'Title' },
      { ' mode:' .. mode .. ' ', 'Special' },
      { ' target:' .. target .. ' ', target == 'prod' and 'DiagnosticError' or 'DiagnosticOk' },
    }
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = 2,
    row = math.floor((vim.o.lines - 2) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = title(),
    title_pos = 'center',
    footer = footer(ctx, width),
    footer_pos = 'center',
  })
  vim.fn.prompt_setprompt(buf, '> ')

  local function refresh()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, { title = title(), title_pos = 'center' })
    end
  end
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    vim.cmd 'stopinsert'
  end

  vim.fn.prompt_setcallback(buf, function(text)
    vim.schedule(function()
      close()
      text = vim.trim(text)
      if text == '' then
        return
      end
      local prompt, parsed = M.parse_prefix(text, mode)
      M.start(prompt, parsed, target, ctx)
    end)
  end)

  local function map(lhs, fn)
    vim.keymap.set({ 'i', 'n' }, lhs, fn, { buffer = buf, nowait = true })
  end
  map('<Tab>', function()
    local index = 1
    for i, m in ipairs(M.MODES) do
      if m == mode then
        index = i
      end
    end
    mode = M.MODES[index % #M.MODES + 1]
    refresh()
  end)
  map('<C-t>', function()
    target = target == 'local' and 'prod' or 'local'
    refresh()
  end)
  map('<C-c>', close)
  map('<Esc>', close)
  vim.keymap.set('n', 'q', close, { buffer = buf, nowait = true })
  vim.cmd 'startinsert'
end

function M.visual()
  local s, e = vim.fn.line 'v', vim.fn.line '.'
  if s > e then
    s, e = e, s
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  M.show { selection = { start_line = s, end_line = e } }
end

---@param entry table
local function restore(entry)
  if state.session then
    M.cancel 'replaced by a resumed run'
  end
  state.run = {
    id = entry.id,
    prompt = entry.prompt,
    mode = entry.mode,
    target = entry.target,
    file = entry.file,
    line = entry.line,
    status = 'idle',
    started = entry.timestamp,
    finished = entry.finished or entry.timestamp,
    plan = entry.plan or {},
    log = {},
    notes = entry.notes or {},
    streaming = '',
    result = entry.result,
  }
  local root = Context.project_root(entry.file)
  state.context = {
    file = entry.file,
    filetype = vim.filetype.match { filename = entry.file } or '',
    root = root,
    project = vim.uv.fs_stat(root .. '/bin/query') and 'phonetrac' or 'generic',
    cursor_line = entry.line,
    dap = Context.dap_state(),
    text = '',
  }
  Panel.open(true)
  render_now()
end

function M.history()
  local history = M.load_history()
  if #history == 0 then
    vim.notify('RunMe: no history yet', vim.log.levels.INFO)
    return
  end
  vim.ui.select(history, {
    prompt = 'RunMe history',
    format_item = function(entry)
      return string.format(
        '%s  %-7s %-5s %s  (%s:%d)',
        os.date('%m-%d %H:%M', entry.timestamp),
        entry.mode,
        entry.target,
        entry.prompt,
        vim.fn.fnamemodify(entry.file, ':t'),
        entry.line
      )
    end,
  }, function(entry)
    if entry then
      restore(entry)
    end
  end)
end

function M.resume()
  if state.run then
    Panel.open(true)
    render_now()
    return
  end
  local last = M.load_history()[1]
  if not last then
    vim.notify('RunMe: nothing to resume', vim.log.levels.INFO)
    return
  end
  restore(last)
end

local did_setup = false

---@param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  if did_setup then
    return
  end
  did_setup = true
  Panel.on_create = map_panel

  vim.api.nvim_create_user_command('RunMe', function(cmd)
    if cmd.range > 0 then
      M.show { selection = { start_line = cmd.line1, end_line = cmd.line2 }, text = cmd.args }
    else
      M.show { text = cmd.args }
    end
  end, { nargs = '*', range = true, desc = 'Run, query, or break on the code under the cursor' })
  vim.api.nvim_create_user_command('RunMeHistory', M.history, { desc = 'Browse RunMe runs' })
  vim.api.nvim_create_user_command('RunMeResume', M.resume, { desc = 'Reopen the RunMe panel' })
  vim.api.nvim_create_user_command('RunMeCancel', function()
    M.cancel 'cancelled by user'
  end, { desc = 'Cancel the RunMe run and clean up the debugger' })

  if M.config.keymap then
    vim.keymap.set('n', M.config.keymap, function()
      M.show()
    end, { desc = 'RunMe: run / query / break here' })
    vim.keymap.set('x', M.config.keymap, M.visual, { desc = 'RunMe: run / query the selection' })
  end

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('runme', { clear = true }),
    callback = function()
      if state.session then
        M.cancel 'nvim exiting'
      end
    end,
  })
end

return M
