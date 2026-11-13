local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(root)
local data = vim.fn.stdpath 'data'
vim.opt.rtp:append(data .. '/site-0.12')
vim.opt.rtp:append(data .. '/lazy-0.12/nvim-dap')

local count = 0
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    io.stderr:write('FAIL: ' .. name .. '\n' .. err .. '\n')
    vim.cmd 'cq'
  end
  count = count + 1
end
local function eq(actual, expected, label)
  if not vim.deep_equal(actual, expected) then
    error(string.format('%s: expected %s, got %s', label or 'eq', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end
local function wait(ms, cond, label)
  if not vim.wait(ms, cond, 10) then
    error('timed out waiting for ' .. (label or 'condition'), 2)
  end
end

local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end

local tmp = assert(vim.uv.fs_realpath(vim.fn.tempname():match '^(.*)/' or '/tmp'))
local project = tmp .. '/runme-project-' .. vim.fn.getpid()
vim.fn.mkdir(project .. '/.git', 'p')
vim.fn.mkdir(project .. '/bin', 'p')
vim.fn.mkdir(project .. '/config', 'p')
vim.fn.writefile({ '' }, project .. '/bin/query')
vim.fn.writefile({ '' }, project .. '/config/application.rb')

local Context = require 'config.runme.context'
local Panel = require 'config.runme.panel'
local Bridge = require 'config.runme.bridge'
local RunMe = require 'config.runme'

local ruby_file = project .. '/call.rb'
vim.fn.writefile({
  'module Billing',
  '  class Call',
  '    def recent(account)',
  '      calls = Call.where(account_id: account.id)',
  '        .order(created_at: :desc)',
  '        .limit(20)',
  '      rows = connection.select_all(<<~SQL)',
  '        SELECT id FROM calls WHERE account_id = 1',
  '      SQL',
  '      RDSC.get("call:#{id}")',
  '      calls',
  '    end',
  '  end',
  'end',
}, ruby_file)

test('context: symbol path, AR chain, SQL heredoc, redis, profile', function()
  vim.cmd.edit(ruby_file)
  vim.bo.filetype = 'ruby'
  vim.treesitter.start(0, 'ruby')
  vim.api.nvim_win_set_cursor(0, { 4, 22 })
  local ctx = Context.capture()
  eq(ctx.project, 'phonetrac', 'profile')
  eq(ctx.root, project, 'root')
  eq(ctx.symbol.path, 'Billing::Call#recent', 'symbol')
  eq(ctx.query.kind, 'ar', 'ar kind')
  eq({ ctx.query.start_line, ctx.query.end_line }, { 4, 6 }, 'ar range')
  assert(ctx.query.text:find('.limit(20)', 1, true), 'whole chain captured')
  assert(ctx.text:find('>4 ', 1, true), 'cursor marker')

  vim.api.nvim_win_set_cursor(0, { 8, 10 })
  ctx = Context.capture()
  eq(ctx.query.kind, 'sql', 'heredoc kind')
  assert(ctx.query.text:find('SELECT id FROM calls', 1, true))

  vim.api.nvim_win_set_cursor(0, { 10, 8 })
  eq(Context.capture().query.kind, 'redis', 'redis kind')

  vim.api.nvim_win_set_cursor(0, { 11, 6 })
  eq(Context.capture().query, nil, 'plain identifier has no query')

  ctx = Context.capture { selection = { start_line = 8, end_line = 8 } }
  eq(ctx.query.kind, 'sql', 'selection classified')
  eq(ctx.dap.attached, false, 'dap not attached')
end)

test('classify and prefix parsing', function()
  eq(Context.classify 'User.find_by(email: x)', 'ar')
  eq(Context.classify '  with x as (select 1) select * from x', 'sql')
  eq(Context.classify '%q(SELECT 1)', 'sql')
  eq(Context.classify 'Call.search(query: { term: 1 })', 'es')
  eq(Context.classify 'foo.bar', nil)
  eq({ RunMe.parse_prefix('? newest 20', 'auto') }, { 'newest 20', 'query' })
  eq({ RunMe.parse_prefix('! here for account 3', 'query') }, { 'here for account 3', 'break' })
  eq({ RunMe.parse_prefix('run it', 'observe') }, { 'run it', 'observe' })
end)

test('panel rendering', function()
  local lines = Panel.table_lines({ 'id', 'name' }, { { 1, 'a' }, { 22, vim.NIL }, { 3, 'c' } }, 2)
  eq(lines[1], 'id │ name', 'header')
  eq(lines[3], '1  │ a', 'row')
  eq(lines[4], '22 │ NULL', 'null cell')
  eq(lines[5], '… 1 more rows (o to open all)', 'overflow')

  local run = {
    id = 'x',
    prompt = 'newest 20',
    mode = 'query',
    target = 'prod',
    file = ruby_file,
    line = 4,
    status = 'awaiting approval',
    started = os.time(),
    plan = { { text = 'build sql', status = 'done' }, { text = 'run', status = 'running', note = 'reader' } },
    log = { { text = 'mysql_dev {}', state = 'ok' } },
    notes = { 'done' },
    streaming = 'partial',
    result = { title = 'calls', columns = { 'id' }, rows = { { 1 } }, query = 'SELECT 1' },
    approval = { id = 'u1', title = 'Run on PROD reader?', message = 'SELECT 1' },
  }
  local text = table.concat((Panel.lines(run)), '\n')
  for _, needle in ipairs { 'RunMe  query · prod', 'Approval needed', '1. ✓ build sql', '2. ⏳ run  — reader', 'Result: calls', 'partial', '✓ mysql_dev' } do
    assert(text:find(needle, 1, true), 'panel missing ' .. needle .. '\n' .. text)
  end
end)

-- Bridge against real nvim-dap breakpoints with a stubbed session layer.
local real_dap = require 'dap'
local breakpoints = require 'dap.breakpoints'
local fake = { sessions = {}, current = nil, requests = {}, listeners = { after = {}, before = {} } }
setmetatable(fake.listeners.after, {
  __index = function(t, k)
    rawset(t, k, {})
    return rawget(t, k)
  end,
})
local function make_session(port)
  local session = { config = { port = port, type = 'ruby' }, sent = {}, closed = false }
  function session:set_breakpoints(bps)
    table.insert(self.sent, bps)
  end
  function session:request(command, args, cb)
    table.insert(fake.requests, { command = command, args = args })
    if command == 'stackTrace' then
      cb(nil, { stackFrames = { { line = 4, name = 'recent', source = { path = ruby_file } } } })
    else
      cb(nil, {})
    end
  end
  function session:evaluate(args, cb)
    cb(nil, { result = '42', type = 'Integer', expr = args.expression })
  end
  function session:disconnect(_, cb)
    self.closed = true
    table.insert(fake.requests, { command = 'disconnect' })
    cb()
  end
  return session
end
package.loaded['dap'] = {
  sessions = function()
    return fake.sessions
  end,
  session = function()
    return fake.current
  end,
  listeners = fake.listeners,
  configurations = { ruby = { { request = 'attach', port = 38698, name = 'attach rails', type = 'ruby' } } },
  run = function(config)
    local session = make_session(config.port)
    fake.sessions[1] = session
    fake.current = session
    for _, fn in pairs(fake.listeners.after['event_initialized_keys'] or {}) do
      fn(session)
    end
    for key, fn in pairs(fake.listeners.after.event_initialized) do
      if key:find 'runme_attach' then
        fn(session)
      end
    end
  end,
  focus_frame = function() end,
}
assert(real_dap)

local function call(op, args)
  local result
  Bridge.handle({ op = op, args = args }, function(ok, value)
    result = { ok = ok, value = value }
  end)
  return result
end

test('bridge: breakpoints are owned, synced, and cleared without touching user breakpoints', function()
  Bridge.reset { root = project }
  local bufnr = vim.fn.bufadd(ruby_file)
  breakpoints.set({}, bufnr, 11)
  local r = call('breakpoint_set', { file = 'call.rb', line = 4, condition = 'account.id == 3' })
  eq(r.ok, true, 'set ok')
  eq(r.value.code, 'calls = Call.where(account_id: account.id)', 'code echo')
  eq(r.value.sent_to_session, false, 'no session yet')
  local bps = breakpoints.get(bufnr)[bufnr]
  eq(#bps, 2, 'user + runme breakpoint')
  eq(call('breakpoint_set', { file = 'call.rb', line = 99 }).ok, false, 'out of range')
  eq(call('breakpoint_set', { file = 'missing.rb', line = 1 }).ok, false, 'missing file')

  eq(call('dap_attach', { target = 'rails' }).value.status, 'attached', 'attach')
  eq(call('dap_attach', { target = 'rails' }).value.status, 'already attached', 'idempotent attach')
  eq(call('dap_attach', { target = 'nope' }).ok, false, 'bad target')

  eq(call('breakpoint_clear', {}).value.removed, 1, 'cleared owned')
  bps = breakpoints.get(bufnr)[bufnr]
  eq(#bps, 1, 'user breakpoint kept')
  eq(bps[1].line, 11, 'user breakpoint line')
  local sent = fake.current.sent[#fake.current.sent]
  eq(#sent[bufnr], 1, 'session got the reduced list')
  breakpoints.clear()
end)

test('bridge: wait_stopped, eval, handoff, and cleanup', function()
  local handed
  Bridge.reset {
    root = project,
    on_handoff = function(message, frame)
      handed = { message = message, frame = frame }
    end,
  }
  local session = fake.current
  eq(call('dap_eval', { expression = 'x' }).ok, false, 'eval needs stop')

  local waited
  Bridge.handle({ op = 'wait_stopped', args = { timeout_s = 5 } }, function(ok, value)
    waited = { ok = ok, value = value }
  end)
  eq(waited, nil, 'still waiting')
  session.stopped_thread_id = 7
  session.current_frame = { id = 1, line = 4, name = 'recent', source = { path = ruby_file } }
  fake.listeners.after.event_stopped['runme'](session, { threadId = 7, reason = 'breakpoint' })
  wait(1000, function()
    return waited ~= nil
  end, 'stop')
  eq(waited.ok, true, 'stopped ok')
  eq({ waited.value.line, waited.value.reason, waited.value.thread }, { 4, 'breakpoint', 7 }, 'stop frame')

  local evaluated
  Bridge.handle({ op = 'dap_eval', args = { expression = 'account.id' } }, function(ok, value)
    evaluated = { ok = ok, value = value }
  end)
  wait(1000, function()
    return evaluated ~= nil
  end, 'eval')
  eq(evaluated.value.result, '42', 'eval result')

  Bridge.state.attached_session = session
  fake.requests = {}
  local actions = Bridge.cleanup()
  eq(actions, { 'resumed suspended thread', 'detached debugger' }, 'cleanup before handoff')
  eq(fake.requests[1].command, 'continue', 'continued')
  eq(fake.requests[1].args.threadId, 7, 'continued the stopped thread')

  session.closed = false
  Bridge.reset {
    root = project,
    on_handoff = function(message, frame)
      handed = { message = message, frame = frame }
    end,
  }
  Bridge.state.attached_session = session
  eq(call('handoff', { message = 'stopped for you' }).ok, true, 'handoff')
  eq(handed.message, 'stopped for you', 'handoff message')
  eq(handed.frame.line, 4, 'handoff frame')
  fake.requests = {}
  eq(Bridge.cleanup(), {}, 'cleanup after handoff leaves the session alone')
  eq(#fake.requests, 0, 'no continue/disconnect after handoff')
  session.stopped_thread_id = nil

  local timed_out
  Bridge.handle({ op = 'wait_stopped', args = { timeout_s = 0 } }, function(ok, value)
    timed_out = { ok = ok, value = value }
  end)
  wait(1000, function()
    return timed_out ~= nil
  end, 'timeout')
  eq(timed_out.ok, false, 'timeout reported')
  eq(call('nope', {}).ok, false, 'unknown op')
end)

-- End-to-end over the RPC pipe with a scripted fake pi.
local fake_pi = tmp .. '/fake-pi-' .. vim.fn.getpid() .. '.py'
vim.fn.writefile({
  'import json, sys',
  'def out(o):',
  '    sys.stdout.write(json.dumps(o) + "\\n"); sys.stdout.flush()',
  'def read():',
  '    return json.loads(sys.stdin.readline())',
  'with open(sys.argv[-1] if False else "/dev/null") as _: pass',
  'args = sys.argv[1:]',
  'prompt = read()',
  'assert prompt["type"] == "prompt", prompt',
  'out({"type": "response", "command": "prompt", "success": True})',
  'out({"type": "agent_start"})',
  'out({"type": "tool_execution_start", "toolCallId": "t1", "toolName": "runme_plan", "args": {"steps": ["inspect", "run"]}})',
  'out({"type": "extension_ui_request", "id": "b1", "method": "input", "title": "runme:bridge", "placeholder": json.dumps({"op": "context", "args": {}})})',
  'reply = read()',
  'ctx = json.loads(reply["value"])',
  'out({"type": "tool_execution_start", "toolCallId": "t2", "toolName": "runme_context", "args": {}})',
  'out({"type": "tool_execution_end", "toolCallId": "t2", "toolName": "runme_context", "isError": False, "result": {"content": [{"type": "text", "text": ctx["result"]["project"] + "|" + str("--exclude-tools" in args) + "|" + str("Request: newest 20" in prompt["message"])}]}})',
  'out({"type": "tool_execution_start", "toolCallId": "t3", "toolName": "runme_step", "args": {"index": 1, "status": "done"}})',
  'out({"type": "extension_ui_request", "id": "c1", "method": "confirm", "title": "Run local command?", "message": "bin/rails runner x"})',
  'answer = read()',
  'out({"type": "tool_execution_start", "toolCallId": "t4", "toolName": "runme_result", "args": {"title": "approved=" + str(answer.get("confirmed")), "columns": ["id"], "rows": [[1], [2]], "query": "SELECT id FROM calls", "language": "sql"}})',
  'out({"type": "message_update", "assistantMessageEvent": {"type": "text_delta", "delta": "Two rows \\u2028 found."}})',
  'out({"type": "message_end", "message": {"role": "assistant"}})',
  'out({"type": "agent_end", "messages": []})',
  'follow = read()',
  'out({"type": "agent_start"})',
  'out({"type": "message_update", "assistantMessageEvent": {"type": "text_delta", "delta": "follow:" + follow["message"]}})',
  'out({"type": "message_end", "message": {"role": "assistant"}})',
  'out({"type": "agent_end", "messages": []})',
  'sys.stdin.readline()',
}, fake_pi)
local runner = tmp .. '/fake-pi-' .. vim.fn.getpid() .. '.sh'
vim.fn.writefile({ '#!/bin/sh', 'exec python3 ' .. vim.fn.shellescape(fake_pi) .. ' "$@"' }, runner)
vim.fn.setfperm(runner, 'rwxr-xr-x')

test('end to end: prompt, bridge reply, approval, result, follow-up, history, cancel', function()
  package.loaded['dap'] = nil
  local history = tmp .. '/runme-history-' .. vim.fn.getpid() .. '.json'
  RunMe.setup {
    keymap = '<leader>hr',
    pi = { executable = runner, mcp = false },
    pi_config_dir = tmp .. '/no-pi-config',
    session_dir = tmp .. '/runme-sessions',
    history_file = history,
  }
  assert(vim.fn.exists ':RunMe' == 2, 'command defined')
  eq(vim.fn.maparg('<leader>hr', 'n') ~= '', true, 'keymap defined')

  vim.cmd.edit(ruby_file)
  vim.api.nvim_win_set_cursor(0, { 4, 22 })
  vim.cmd 'RunMe ? newest 20'
  local state = RunMe._state
  eq(state.run.mode, 'query', 'prefix mode')
  eq(state.run.prompt, 'newest 20', 'prompt text')
  assert(Panel.win(), 'panel open')

  wait(5000, function()
    return state.run.approval ~= nil
  end, 'approval request: ' .. vim.inspect { state.run.status, state.run.log, state.run.plan })
  eq(state.run.status, 'awaiting approval', 'status')
  eq(state.run.plan[1].status, 'done', 'step applied')
  local ctx_entry = state.run.log[1]
  eq(ctx_entry.state, 'ok', 'context tool finished')
  assert(ctx_entry.text:find('phonetrac|True|True', 1, true), 'bridge context round-trip: ' .. ctx_entry.text)

  vim.api.nvim_set_current_win(Panel.win())
  vim.api.nvim_feedkeys('a', 'x', false)
  wait(5000, function()
    return state.run.status == 'idle'
  end, 'agent_end')
  eq(state.run.result.title, 'approved=True', 'approval answered')
  eq(#state.run.result.rows, 2, 'rows')
  eq(state.run.notes[1], 'Two rows \u{2028} found.', 'LF-only framing keeps U+2028')
  local saved = RunMe.load_history()
  eq(saved[1].id, state.run.id, 'history recorded')

  RunMe.follow_up 'again'
  wait(5000, function()
    return state.run.notes[#state.run.notes] == 'follow:again'
  end, 'follow-up')

  RunMe.cancel 'test done'
  eq(state.run.status, 'cancelled', 'cancelled')
  eq(state.session, nil, 'session stopped')
  vim.fn.delete(history)
end)

vim.fn.delete(project, 'rf')
vim.fn.delete(fake_pi)
vim.fn.delete(runner)
print(string.format('%d runme checks passed', count))
vim.cmd 'qa!'
