local Context = require 'config.runme.context'

local M = {}

M.PORTS = { rails = 38698, worker = 38699 }
M.attach_timeout_ms = 15000

---@class runme.BridgeState
---@field root string
---@field source_win? integer
---@field owned { bufnr: integer, line: integer }[]
---@field attached_session? table
---@field handed_off boolean
---@field waiters { reply: fun(ok: boolean, result: any), timer: uv.uv_timer_t }[]
---@field on_handoff? fun(message: string, frame?: table)

---@type runme.BridgeState
M.state = { root = '', owned = {}, handed_off = false, waiters = {} }

---@param opts { root: string, source_win?: integer, on_handoff?: fun(message: string, frame?: table) }
function M.reset(opts)
  M.state = {
    root = opts.root,
    source_win = opts.source_win,
    owned = {},
    handed_off = false,
    waiters = {},
    on_handoff = opts.on_handoff,
  }
end

local function dap()
  return require 'dap'
end

---@param timer uv.uv_timer_t
local function close_timer(timer)
  timer:stop()
  if not timer:is_closing() then
    timer:close()
  end
end

---@param ms integer
---@param fn fun()
---@return uv.uv_timer_t
local function after(ms, fn)
  local timer = assert(vim.uv.new_timer())
  timer:start(ms, 0, vim.schedule_wrap(fn))
  return timer
end

---@param path string
---@return string
local function resolve(path)
  if path:sub(1, 1) == '/' then
    return vim.fs.normalize(path)
  end
  return vim.fs.normalize(M.state.root .. '/' .. path)
end

---@param bufnr integer
---@param on_done? fun()
local function sync_breakpoints(bufnr, on_done)
  local bps = require('dap.breakpoints').get(bufnr)[bufnr] or {}
  local pending = vim.tbl_count(dap().sessions())
  if pending == 0 then
    if on_done then
      on_done()
    end
    return
  end
  for _, session in pairs(dap().sessions()) do
    session:set_breakpoints({ [bufnr] = bps }, function()
      pending = pending - 1
      if pending == 0 and on_done then
        on_done()
      end
    end)
  end
end

---@param bufnr integer
---@param line integer
---@return table|nil
local function breakpoint_state(bufnr, line)
  for _, bp in ipairs(require('dap.breakpoints').get(bufnr)[bufnr] or {}) do
    if bp.line == line then
      return bp.state
    end
  end
  return nil
end

---@param file string|nil
---@param line integer|nil
---@return 'runme'|'user'|'other'
function M.classify_stop(file, line)
  if not (file and line) then
    return 'other'
  end
  for _, bp in ipairs(M.state.owned) do
    if vim.api.nvim_buf_is_valid(bp.bufnr) and vim.api.nvim_buf_get_name(bp.bufnr) == file and bp.line == line then
      return 'runme'
    end
  end
  local bufnr = vim.fn.bufnr(file)
  if bufnr ~= -1 then
    for _, bp in ipairs(require('dap.breakpoints').get(bufnr)[bufnr] or {}) do
      if bp.line == line then
        return 'user'
      end
    end
  end
  return 'other'
end

---@return table[]
local function owned_list()
  return vim.tbl_map(function(bp)
    local bp_state = vim.api.nvim_buf_is_valid(bp.bufnr) and breakpoint_state(bp.bufnr, bp.line) or nil
    return {
      file = vim.api.nvim_buf_get_name(bp.bufnr),
      line = bp.line,
      adapter_verified = bp_state and bp_state.verified,
      adapter_message = bp_state and bp_state.message,
    }
  end, M.state.owned)
end

---@param frame table|nil
---@param extra table
---@return table
local function stop_report(frame, extra)
  frame = frame or {}
  return vim.tbl_extend('force', frame, extra, {
    hit = M.classify_stop(frame.file, frame.line),
    runme_breakpoints = owned_list(),
  })
end

---@param session table
---@param thread_id integer
---@param cb fun(frame: table|nil)
local function top_frame(session, thread_id, cb)
  session:request('stackTrace', { threadId = thread_id, startFrame = 0, levels = 1 }, function(err, resp)
    local frame = not err and resp and resp.stackFrames and resp.stackFrames[1]
    if not frame then
      cb(nil)
      return
    end
    cb {
      file = frame.source and (frame.source.path or frame.source.name),
      line = frame.line,
      name = frame.name,
      thread = thread_id,
    }
  end)
end

---@param ok boolean
---@param result any
local function resolve_waiters(ok, result)
  local waiters = M.state.waiters
  M.state.waiters = {}
  for _, waiter in ipairs(waiters) do
    close_timer(waiter.timer)
    waiter.reply(ok, result)
  end
end

local listeners_installed = false
local function install_listeners()
  if listeners_installed then
    return
  end
  listeners_installed = true
  local d = dap()
  d.listeners.after.event_stopped['runme'] = function(session, body)
    if #M.state.waiters == 0 then
      return
    end
    top_frame(session, body.threadId, function(frame)
      vim.schedule(function()
        resolve_waiters(true, stop_report(frame, { reason = body.reason, thread = body.threadId, description = body.description or body.text }))
      end)
    end)
  end
  local function ended(session)
    if M.state.attached_session == session then
      M.state.attached_session = nil
    end
    resolve_waiters(false, 'debug session ended before a stop')
  end
  d.listeners.after.event_terminated['runme'] = ended
  d.listeners.after.disconnect['runme'] = ended
end

---@type table<string, fun(args: table, reply: fun(ok: boolean, result: any))>
local handlers = {}

function handlers.context(_, reply)
  local win = M.state.source_win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    win = vim.api.nvim_get_current_win()
  end
  reply(true, Context.public(Context.capture { win = win }))
end

function handlers.dap_status(_, reply)
  local state = Context.dap_state()
  state.runme_breakpoints = owned_list()
  state.handed_off = M.state.handed_off
  reply(true, state)
end

---@param port integer
---@return table|nil
local function session_on_port(port)
  for _, session in pairs(dap().sessions()) do
    if tonumber(session.config.port) == port then
      return session
    end
  end
  return nil
end

--- rdbg serves one DAP client; a second attach hangs instead of failing, so find
--- an existing client first.
---@param port integer
---@return { pid: integer, command: string }|nil
function M.port_holder(port)
  local result = vim.system({ 'lsof', '-nP', '-iTCP:' .. port, '-sTCP:ESTABLISHED', '-Fpcn' }, { text = true }):wait(3000)
  if result.code ~= 0 or not result.stdout then
    return nil
  end
  local pid, command
  local suffix = ':' .. port
  for line in result.stdout:gmatch '[^\n]+' do
    local tag, value = line:sub(1, 1), line:sub(2)
    if tag == 'p' then
      pid = tonumber(value)
    elseif tag == 'c' then
      command = value
    elseif tag == 'n' and value:sub(-#suffix) == suffix and value:find('->', 1, true) and pid ~= vim.fn.getpid() then
      return { pid = pid, command = command }
    end
  end
  return nil
end

function handlers.dap_attach(args, reply)
  local port = args.target == 'port' and tonumber(args.port) or M.PORTS[args.target]
  if not port then
    reply(false, 'unknown attach target: ' .. tostring(args.target))
    return
  end
  install_listeners()
  local existing = session_on_port(port)
  if existing then
    reply(true, { port = port, status = 'already attached' })
    return
  end
  local holder = M.port_holder(port)
  if holder then
    reply(
      false,
      string.format(
        'rdbg on port %d already has a debugger client (%s pid %d). rdbg accepts one client: run RunMe from that editor, or disconnect it there, then retry.',
        port,
        holder.command or '?',
        holder.pid
      )
    )
    return
  end
  local config
  for _, c in ipairs(dap().configurations.ruby or {}) do
    if c.request == 'attach' and tonumber(c.port) == port then
      config = c
      break
    end
  end
  config = config
    or {
      type = 'ruby',
      request = 'attach',
      name = 'runme attach ' .. port,
      port = port,
      waiting = 0,
      localfs = true,
      options = { source_filetype = 'ruby' },
    }

  local done = false
  local key = 'runme_attach_' .. port
  local timer
  local function finish(ok, result)
    if done then
      return
    end
    done = true
    dap().listeners.after.event_initialized[key] = nil
    if timer then
      close_timer(timer)
    end
    reply(ok, result)
  end
  dap().listeners.after.event_initialized[key] = function(session)
    if tonumber(session.config.port) == port then
      M.state.attached_session = session
      finish(true, { port = port, status = 'attached' })
    end
  end
  timer = after(M.attach_timeout_ms, function()
    local stuck = session_on_port(port)
    if stuck then
      stuck:close()
    end
    finish(false, string.format('could not attach to rdbg on port %d; is the process running under rdbg?', port))
  end)
  dap().run(config, { new = true })
end

function handlers.breakpoint_set(args, reply)
  local path = resolve(args.file)
  if not vim.uv.fs_stat(path) then
    reply(false, 'no such file: ' .. path)
    return
  end
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  local line = tonumber(args.line)
  if not line or line < 1 or line > vim.api.nvim_buf_line_count(bufnr) then
    reply(false, string.format('line %s is outside %s', tostring(args.line), path))
    return
  end
  install_listeners()
  require('dap.breakpoints').set({
    condition = args.condition,
    hit_condition = args.hit_condition,
    log_message = args.log_message,
  }, bufnr, line)
  table.insert(M.state.owned, { bufnr = bufnr, line = line })
  local attached = next(dap().sessions()) ~= nil
  local timer, responded
  local function respond()
    if responded then
      return
    end
    responded = true
    if timer then
      close_timer(timer)
    end
    local bp_state = breakpoint_state(bufnr, line)
    reply(true, {
      file = path,
      line = line,
      condition = args.condition,
      code = vim.trim(vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''),
      sent_to_session = attached,
      adapter_verified = bp_state and bp_state.verified,
      adapter_message = bp_state and bp_state.message,
    })
  end
  timer = after(5000, respond)
  sync_breakpoints(bufnr, vim.schedule_wrap(respond))
end

---@return integer removed
function M.clear_owned()
  if not package.loaded['dap'] then
    M.state.owned = {}
    return 0
  end
  local breakpoints = require 'dap.breakpoints'
  local buffers = {}
  for _, bp in ipairs(M.state.owned) do
    if vim.api.nvim_buf_is_valid(bp.bufnr) then
      breakpoints.remove(bp.bufnr, bp.line)
      buffers[bp.bufnr] = true
    end
  end
  local removed = #M.state.owned
  M.state.owned = {}
  for bufnr in pairs(buffers) do
    sync_breakpoints(bufnr)
  end
  return removed
end

function handlers.breakpoint_remove(args, reply)
  local path = resolve(args.file)
  local line = tonumber(args.line)
  for i, bp in ipairs(M.state.owned) do
    if vim.api.nvim_buf_is_valid(bp.bufnr) and vim.api.nvim_buf_get_name(bp.bufnr) == path and bp.line == line then
      require('dap.breakpoints').remove(bp.bufnr, line)
      table.remove(M.state.owned, i)
      sync_breakpoints(bp.bufnr)
      reply(true, { removed = { file = path, line = line } })
      return
    end
  end
  reply(false, string.format('no RunMe breakpoint at %s:%s', path, tostring(args.line)))
end

function handlers.breakpoint_clear(_, reply)
  reply(true, { removed = M.clear_owned() })
end

function handlers.wait_stopped(args, reply)
  install_listeners()
  local session = dap().session()
  if session and session.stopped_thread_id then
    top_frame(session, session.stopped_thread_id, function(frame)
      vim.schedule(function()
        reply(true, stop_report(frame, { reason = 'already stopped', thread = session.stopped_thread_id }))
      end)
    end)
    return
  end
  if not session then
    reply(false, 'no debug session; call runme_dap_attach first')
    return
  end
  local waiter = { reply = reply }
  waiter.timer = after((tonumber(args.timeout_s) or 300) * 1000, function()
    M.state.waiters = vim.tbl_filter(function(w)
      return w ~= waiter
    end, M.state.waiters)
    reply(false, 'timed out waiting for a breakpoint hit; call runme_trigger_status to see whether the trigger reached the debugged process')
  end)
  table.insert(M.state.waiters, waiter)
end

function handlers.continue(args, reply)
  if M.state.handed_off then
    reply(false, 'the debugger belongs to the user after handoff')
    return
  end
  local session = dap().session()
  if not (session and session.stopped_thread_id) then
    reply(false, 'debugger is not stopped')
    return
  end
  local thread = session.stopped_thread_id
  session:request('continue', { threadId = thread }, function(err)
    vim.schedule(function()
      if err then
        reply(false, err.message or vim.inspect(err))
      else
        reply(true, { continued = thread, reason = args.reason })
      end
    end)
  end)
end

function handlers.dap_eval(args, reply)
  local session = dap().session()
  if not (session and session.stopped_thread_id) then
    reply(false, 'debugger is not stopped')
    return
  end
  local frame = session.current_frame
  session:evaluate({ expression = args.expression, context = 'repl', frameId = frame and frame.id }, function(err, resp)
    vim.schedule(function()
      if err then
        reply(false, err.message or vim.inspect(err))
      else
        reply(true, { result = resp.result, type = resp.type })
      end
    end)
  end)
end

function handlers.handoff(args, reply)
  M.state.handed_off = true
  local session = dap().session()
  local frame = session and session.current_frame
  local ok, dapui = pcall(require, 'dapui')
  if ok then
    local opened, err = pcall(dapui.open, {})
    if not opened then
      vim.notify('RunMe: dap-ui failed to open: ' .. tostring(err), vim.log.levels.WARN)
    end
  end
  if session and session.stopped_thread_id then
    pcall(dap().focus_frame)
  end
  if M.state.on_handoff then
    M.state.on_handoff(args.message or '', frame and {
      file = frame.source and frame.source.path,
      line = frame.line,
      name = frame.name,
    } or nil)
  end
  reply(true, { handed_off = true })
end

---@param request { op: string, args?: table }
---@param reply fun(ok: boolean, result: any)
function M.handle(request, reply)
  local handler = handlers[request.op]
  if not handler then
    reply(false, 'unknown bridge op: ' .. tostring(request.op))
    return
  end
  local replied = false
  local function once(ok, result)
    if replied then
      return
    end
    replied = true
    reply(ok, result)
  end
  local ok, err = pcall(handler, request.args or {}, once)
  if not ok then
    once(false, tostring(err))
  end
end

--- Undo RunMe's debugger changes. Before handoff this also resumes a suspended
--- thread and detaches a session RunMe attached, so the dev app never stays frozen.
---@return string[] actions
function M.cleanup()
  local actions = {}
  resolve_waiters(false, 'run cancelled')
  local removed = M.clear_owned()
  if removed > 0 then
    table.insert(actions, string.format('removed %d breakpoint(s)', removed))
  end
  if M.state.handed_off or not package.loaded['dap'] then
    return actions
  end
  local session = dap().session()
  if session and session.stopped_thread_id then
    session:request('continue', { threadId = session.stopped_thread_id }, function() end)
    table.insert(actions, 'resumed suspended thread')
  end
  local attached = M.state.attached_session
  if attached and not attached.closed then
    attached:disconnect({ terminateDebuggee = false }, function() end)
    table.insert(actions, 'detached debugger')
  end
  M.state.attached_session = nil
  return actions
end

M._handlers = handlers

return M
