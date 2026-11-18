local M = {}

---@alias PseudoEvalProvenance 'literal'|'derived'|'mock'

---@class PseudoEvalResult
---@field type string
---@field shape string
---@field value string
---@field provenance PseudoEvalProvenance
---@field basis string
---@field repl string

---@class PseudoEvalEntry
---@field id integer
---@field key string
---@field expr string
---@field line_text string
---@field bufnr integer
---@field filename string
---@field filetype string
---@field lnum integer 1-based
---@field mark integer? extmark id that tracks the line through edits
---@field timestamp integer
---@field result PseudoEvalResult

M.config = {
  pi = vim.fn.stdpath 'config' .. '/bin/pi-mise',
  model = nil, ---@type string? pi --model pattern; nil uses pi's default
  thinking = 'low',
  timeout = 90000,
  lines_above = 150,
  lines_below = 40,
  hover_timeout = 800,
  max_width = 90,
  max_height = 30,
  annotate = true,
}

local ns = vim.api.nvim_create_namespace 'pseudo_eval'
local FOCUS_ID = 'pseudo_eval'
local SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

---@type PseudoEvalEntry[]
local entries = {}
---@type table<string, true>
local pending = {}
local next_id = 1

local PROVENANCE_HL = {
  literal = 'DiagnosticOk',
  derived = 'DiagnosticInfo',
  mock = 'DiagnosticWarn',
}

local PROVENANCE_ICON = {
  literal = '●',
  derived = '◐',
  mock = '○',
}

local PROMPT =
  [=[You are a pseudo-debugger. The user has just stepped over the marked line in a debugger and wants to inspect the value of an expression. You cannot run the code. Produce the value the expression would most plausibly hold right after the marked line executes: if the line assigns it, show the assigned value; if the expression is evaluated on that line, show what it evaluates to there. Never answer nil/null/undefined merely because a variable is unassigned before the line runs.

Decide the provenance:
- "literal": the value follows directly from literals or constants visible in the code.
- "derived": you grounded it in real data you found (constants, schema files, fixtures, factories, type definitions, test data, sample payloads). Use your read/grep/find tools for this, but keep it to a few quick lookups.
- "mock": nothing concrete was available, so you invented plausible data consistent with names, types and usage.

Respond with ONLY one JSON object, no prose and no code fences:
{
  "type": "the runtime type in the language's own notation, e.g. Array<Hash{Symbol => String}>, list[dict[str, int]], Map<string, User>",
  "shape": "one short line describing structure and size, e.g. 3 × {id: Integer, name: String, tags: Array<String>}",
  "value": "the value written as a %s literal that would reconstruct it, pretty-printed, at most 25 lines; abbreviate long collections with 2-3 elements and a trailing comment giving the full count",
  "provenance": "literal | derived | mock",
  "basis": "a short phrase naming where the data came from, e.g. db/schema.rb `calls` table, or naming conventions only",
  "repl": "%s code that assigns this value to a variable named after the expression (snake_case if the expression is not a valid name), loading anything required, ready to paste into a REPL"
}
]=]

---@param msg string
---@param level? integer
local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'pseudo-eval' })
end

---@param text string
---@param max integer
---@return string
local function ellipsize(text, max)
  text = text:gsub('%s+', ' ')
  if vim.fn.strchars(text) <= max then
    return text
  end
  return vim.fn.strcharpart(text, 0, max - 1) .. '…'
end

---@param bufnr integer
---@return string
local function project_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then
    return vim.uv.cwd() or '.'
  end
  return vim.fs.root(path, { '.git' }) or vim.fs.dirname(path)
end

---@param ft string
---@return string
local function language_name(ft)
  if ft == '' then
    return 'source'
  end
  return ft
end

local MEMBER_FIELDS = { 'property', 'field', 'attribute', 'method', 'name', 'index', 'subscript', 'function' }

---Return the expression the cursor is on. On `bar` in `foo.bar(1).baz` it returns `foo.bar(1)`:
---a member or callee alone is rarely what you want to inspect, its result is.
---@param bufnr integer
---@return string?
local function expression_at_cursor(bufnr)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, ignore_injections = false })
  if not ok or not node then
    local word = vim.fn.expand '<cword>'
    return word ~= '' and word or nil
  end

  local function is_member_of(child, parent)
    for _, field in ipairs(MEMBER_FIELDS) do
      for _, n in ipairs(parent:field(field)) do
        if n:equal(child) then
          return true
        end
      end
    end
    return false
  end

  while node:parent() and is_member_of(node, node:parent()) do
    node = node:parent()
  end

  local text = vim.treesitter.get_node_text(node, bufnr)
  if not text:find '\n' and #text <= 200 then
    return text
  end
  local word = vim.fn.expand '<cword>'
  if word ~= '' and not word:match '^%s*$' then
    return word
  end
  local line = vim.trim(vim.api.nvim_get_current_line())
  return line ~= '' and line or nil
end

---@return string?
local function visual_selection()
  local lines = vim.fn.getregion(vim.fn.getpos 'v', vim.fn.getpos '.', { type = vim.fn.mode() })
  local text = vim.trim(table.concat(lines, '\n'))
  return text ~= '' and text or nil
end

---@param bufnr integer
---@param row integer 1-based
---@return string
local function code_context(bufnr, row)
  local first = math.max(1, row - M.config.lines_above)
  local last = math.min(vim.api.nvim_buf_line_count(bufnr), row + M.config.lines_below)
  local out = {}
  for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)) do
    local lnum = first + i - 1
    out[#out + 1] = string.format('%s%5d  %s', lnum == row and '>' or ' ', lnum, line)
  end
  return table.concat(out, '\n')
end

---LSP hover often knows the declared type; it grounds the model for free.
---@param bufnr integer
---@param win integer
---@param callback fun(text: string?)
local function lsp_hover(bufnr, win, callback)
  if #vim.lsp.get_clients { bufnr = bufnr, method = 'textDocument/hover' } == 0 then
    callback(nil)
    return
  end

  local done = false
  local function finish(text)
    if not done then
      done = true
      callback(text)
    end
  end

  vim.defer_fn(function()
    finish(nil)
  end, M.config.hover_timeout)

  vim.lsp.buf_request_all(bufnr, 'textDocument/hover', function(client)
    return vim.lsp.util.make_position_params(win, client.offset_encoding)
  end, function(results)
    local parts = {}
    for _, res in pairs(results) do
      local contents = res.result and res.result.contents
      if contents then
        local lines = vim.lsp.util.convert_input_to_markdown_lines(contents)
        local text = vim.trim(table.concat(lines, '\n'))
        if text ~= '' then
          parts[#parts + 1] = text
        end
      end
    end
    finish(#parts > 0 and table.concat(parts, '\n---\n') or nil)
  end)
end

---@param raw string
---@return PseudoEvalResult?, string?
local function parse_result(raw)
  local start = raw:find('{', 1, true)
  local stop = raw:match '.*()}'
  if not start or not stop then
    return nil, 'no JSON object in response'
  end
  local json = raw:sub(start, stop)

  local ok, data = pcall(vim.json.decode, json, { luanil = { object = true } })
  if not ok or type(data) ~= 'table' then
    return nil, 'invalid JSON in response'
  end

  local provenance = PROVENANCE_HL[data.provenance] and data.provenance or 'mock'
  return {
    type = tostring(data.type or '?'),
    shape = tostring(data.shape or ''),
    value = tostring(data.value or ''),
    provenance = provenance,
    basis = tostring(data.basis or ''),
    repl = tostring(data.repl or ''),
  }
end

---@param target { expr: string, bufnr: integer, filename: string, filetype: string, lnum: integer, line_text: string }
---@param hover string?
---@param callback fun(result: PseudoEvalResult?, err: string?)
local function ask_pi(target, hover, callback)
  local lang = language_name(target.filetype)
  local parts = {
    PROMPT:format(lang, lang),
    'File: ' .. target.filename .. ' (' .. lang .. ')',
    'Paused at line ' .. target.lnum .. ': ' .. vim.trim(target.line_text),
    'Expression to inspect: ' .. target.expr,
  }
  if hover then
    parts[#parts + 1] = 'Language server hover for the expression:\n' .. hover
  end
  parts[#parts + 1] = 'Code (the > marks the paused line):\n' .. code_context(target.bufnr, target.lnum)

  local args = {
    M.config.pi,
    '-p',
    '--no-session',
    '--no-extensions',
    '--no-skills',
    '--no-prompt-templates',
    '--no-themes',
    '--no-context-files',
    '--thinking',
    M.config.thinking,
    '--tools',
    'read,grep,find,ls',
  }
  if M.config.model then
    vim.list_extend(args, { '--model', M.config.model })
  end
  args[#args + 1] = table.concat(parts, '\n\n')

  local ok, proc = pcall(vim.system, args, {
    cwd = project_root(target.bufnr),
    text = true,
    timeout = M.config.timeout,
  }, function(obj)
    if obj.code ~= 0 then
      local detail = vim.trim(obj.stderr or '')
      if obj.signal == 15 or obj.code == 124 then
        detail = 'timed out after ' .. (M.config.timeout / 1000) .. 's'
      end
      callback(nil, detail ~= '' and detail or ('pi exited ' .. obj.code))
      return
    end
    local result, err = parse_result(obj.stdout or '')
    if not result then
      callback(nil, err .. ':\n' .. vim.trim(obj.stdout or ''))
      return
    end
    callback(result)
  end)
  if not ok then
    callback(nil, 'failed to start pi: ' .. tostring(proc))
  end
end

---@param entry PseudoEvalEntry
---@return integer? lnum 1-based current line of the entry, following edits
local function entry_lnum(entry)
  if not vim.api.nvim_buf_is_valid(entry.bufnr) or not entry.mark then
    return entry.lnum
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(entry.bufnr, ns, entry.mark, {})
  return pos[1] and pos[1] + 1 or entry.lnum
end

---@param bufnr integer
local function render_annotations(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local by_line = {} ---@type table<integer, PseudoEvalEntry[]>
  for _, entry in ipairs(entries) do
    if entry.bufnr == bufnr and entry.mark then
      local lnum = entry_lnum(entry)
      if lnum then
        by_line[lnum] = by_line[lnum] or {}
        table.insert(by_line[lnum], entry)
      end
    end
  end

  for _, list in pairs(by_line) do
    local chunks = { { '  ', 'Normal' } }
    for i, entry in ipairs(list) do
      if i > 1 then
        chunks[#chunks + 1] = { '  ', 'Comment' }
      end
      local r = entry.result
      chunks[#chunks + 1] = { PROVENANCE_ICON[r.provenance] .. ' ', PROVENANCE_HL[r.provenance] }
      chunks[#chunks + 1] = { ellipsize(entry.expr, 24) .. ': ', 'Comment' }
      chunks[#chunks + 1] = { r.type, 'Comment' }
    end
    local anchor = list[#list]
    vim.api.nvim_buf_set_extmark(bufnr, ns, entry_lnum(anchor) - 1, 0, {
      id = anchor.mark,
      virt_text = M.config.annotate and chunks or nil,
      virt_text_pos = 'eol',
      hl_mode = 'combine',
      invalidate = true,
    })
    for _, other in ipairs(list) do
      if other ~= anchor then
        vim.api.nvim_buf_set_extmark(bufnr, ns, entry_lnum(other) - 1, 0, { id = other.mark, invalidate = true })
      end
    end
  end
end

---@param entry PseudoEvalEntry
---@return string[]
local function markdown_lines(entry)
  local r = entry.result
  local lines = {
    '`' .. r.type .. '`',
  }
  if r.shape ~= '' then
    lines[#lines + 1] = r.shape
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '```' .. entry.filetype
  vim.list_extend(lines, vim.split(r.value, '\n', { plain = true }))
  lines[#lines + 1] = '```'
  if r.basis ~= '' then
    lines[#lines + 1] = ''
    lines[#lines + 1] = '*' .. r.provenance .. '* — ' .. r.basis
  end
  return lines
end

local open_split, send_to_repl, evaluate

---@param entry PseudoEvalEntry
---@param opts? { focus?: boolean, at_cursor?: boolean }
local function show_entry(entry, opts)
  opts = opts or {}
  local r = entry.result
  local _, win = vim.lsp.util.open_floating_preview(markdown_lines(entry), 'markdown', {
    border = 'rounded',
    focus_id = FOCUS_ID,
    focus = opts.focus ~= false,
    max_width = M.config.max_width,
    max_height = M.config.max_height,
    title = {
      { ' ' .. PROVENANCE_ICON[r.provenance] .. ' ', PROVENANCE_HL[r.provenance] },
      { ellipsize(entry.expr, 60) .. ' ', 'FloatTitle' },
    },
    title_pos = 'left',
    close_events = opts.at_cursor == false and {} or nil,
  })
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  vim.wo[win].concealcursor = 'n'

  if opts.at_cursor == false then
    local cfg = vim.api.nvim_win_get_config(win)
    cfg.relative = 'editor'
    cfg.row = math.floor((vim.o.lines - cfg.height) / 2) - 1
    cfg.col = math.floor((vim.o.columns - cfg.width) / 2)
    vim.api.nvim_win_set_config(win, cfg)
    vim.api.nvim_set_current_win(win)
  end

  pcall(vim.api.nvim_win_set_config, win, {
    footer = { { ' y yank · s split · r repl · R rerun · o goto ', 'FloatFooter' } },
    footer_pos = 'right',
  })

  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  map('q', close, 'Close')
  map('<Esc>', close, 'Close')
  map('y', function()
    vim.fn.setreg('+', r.value)
    notify('Value yanked: ' .. entry.expr)
  end, 'Yank value')
  map('Y', function()
    vim.fn.setreg('+', r.repl)
    notify('REPL snippet yanked: ' .. entry.expr)
  end, 'Yank REPL snippet')
  map('s', function()
    close()
    open_split(entry)
  end, 'Open in split')
  map('r', function()
    close()
    send_to_repl(entry)
  end, 'Send to REPL')
  map('R', function()
    close()
    M.goto_entry(entry)
    evaluate { expr = entry.expr, force = true }
  end, 'Re-evaluate')
  map('o', function()
    close()
    M.goto_entry(entry)
  end, 'Go to source line')
end

---@param entry PseudoEvalEntry
open_split = function(entry)
  local name = 'pseudo-eval://' .. entry.id .. '/' .. entry.expr
  local existing = vim.fn.bufnr(name)
  vim.cmd 'botright vsplit'
  if existing ~= -1 then
    vim.api.nvim_win_set_buf(0, existing)
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = 'hide'
  local r = entry.result
  local header = {
    string.format('%s: %s', entry.expr, r.type),
    r.shape,
    string.format('%s — %s', r.provenance, r.basis),
    string.format('%s:%d', vim.fn.fnamemodify(entry.filename, ':~:.'), entry_lnum(entry)),
  }
  local cs = vim.api.nvim_buf_is_valid(entry.bufnr) and vim.bo[entry.bufnr].commentstring or ''
  if cs == '' or not cs:find '%%s' then
    cs = '# %s'
  end
  local lines = {}
  for _, h in ipairs(header) do
    if h ~= '' then
      lines[#lines + 1] = cs:format(h)
    end
  end
  lines[#lines + 1] = ''
  vim.list_extend(lines, vim.split(r.repl ~= '' and r.repl or r.value, '\n', { plain = true }))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, buf)
  vim.bo[buf].filetype = entry.filetype
  vim.b[buf].pseudo_eval_entry = entry.id
end

---@param entry PseudoEvalEntry
send_to_repl = function(entry)
  local ok, iron = pcall(require, 'iron.core')
  if not ok then
    notify('iron.nvim is not available', vim.log.levels.ERROR)
    return
  end
  local code = entry.result.repl ~= '' and entry.result.repl or entry.result.value
  local sent, err = pcall(iron.send, entry.filetype, vim.split(code, '\n', { plain = true }))
  if not sent then
    notify('REPL send failed: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end
  notify('Sent to ' .. entry.filetype .. ' REPL: ' .. entry.expr)
end

---@param entry PseudoEvalEntry
function M.goto_entry(entry)
  if vim.api.nvim_buf_is_valid(entry.bufnr) then
    vim.api.nvim_set_current_buf(entry.bufnr)
  else
    vim.cmd.edit(vim.fn.fnameescape(entry.filename))
  end
  local lnum = math.min(entry_lnum(entry) or entry.lnum, vim.api.nvim_buf_line_count(0))
  local col = (vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ''):find(entry.expr, 1, true)
  vim.api.nvim_win_set_cursor(0, { lnum, col and col - 1 or 0 })
end

---@param bufnr integer
---@param lnum integer
---@param expr string
---@param line_text string
---@return string
local function entry_key(bufnr, lnum, expr, line_text)
  return table.concat({ vim.api.nvim_buf_get_name(bufnr), lnum, expr, vim.trim(line_text) }, '\0')
end

---@param key string
---@return PseudoEvalEntry?, integer?
local function find_entry(key)
  for i, entry in ipairs(entries) do
    if entry.key == key then
      return entry, i
    end
  end
end

---Loading indicator anchored at the cursor; closes itself if the cursor leaves.
---@param expr string
---@return fun() stop
local function loading_float(expr)
  local buf = vim.api.nvim_create_buf(false, true)
  local text = ' evaluating ' .. expr .. ' '
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  local width = math.min(vim.fn.strdisplaywidth(text) + 2, M.config.max_width)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = 1,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = 'Normal:Comment'

  local frame = 0
  local timer = assert(vim.uv.new_timer())
  local src_buf = vim.api.nvim_get_current_buf()
  local function stop()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  timer:start(
    0,
    90,
    vim.schedule_wrap(function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      frame = frame % #SPINNER + 1
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { SPINNER[frame] .. text })
    end)
  )
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufLeave' }, {
    buffer = src_buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
  return stop
end

---@param opts? { expr?: string, force?: boolean }
evaluate = function(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum = cursor[1]
  local line_text = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''

  local expr = opts.expr
  if not expr then
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
      expr = visual_selection()
      vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
    else
      expr = expression_at_cursor(bufnr)
    end
  end
  if not expr or vim.trim(line_text) == '' then
    notify('Nothing to evaluate here', vim.log.levels.WARN)
    return
  end

  local key = entry_key(bufnr, lnum, expr, line_text)
  local cached, cached_idx = find_entry(key)
  if cached and not opts.force then
    show_entry(cached)
    return
  end
  if pending[key] then
    notify('Already evaluating ' .. expr)
    return
  end
  pending[key] = true
  vim.cmd.redrawstatus()

  local target = {
    expr = expr,
    bufnr = bufnr,
    filename = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    lnum = lnum,
    line_text = line_text,
  }
  local stop_loading = loading_float(expr)

  lsp_hover(bufnr, win, function(hover)
    ask_pi(target, hover, function(result, err)
      vim.schedule(function()
        pending[key] = nil
        stop_loading()
        vim.cmd.redrawstatus()
        if not result then
          notify('pseudo-eval ' .. expr .. ' failed: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
          return
        end

        if cached_idx then
          if cached and cached.mark and vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, cached.mark)
          end
          table.remove(entries, cached_idx)
        end

        ---@type PseudoEvalEntry
        local entry = {
          id = next_id,
          key = key,
          expr = expr,
          line_text = line_text,
          bufnr = bufnr,
          filename = target.filename,
          filetype = target.filetype,
          lnum = lnum,
          timestamp = os.time(),
          result = result,
        }
        next_id = next_id + 1
        if vim.api.nvim_buf_is_valid(bufnr) and lnum <= vim.api.nvim_buf_line_count(bufnr) then
          entry.mark = vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, { invalidate = true })
        end
        table.insert(entries, 1, entry)
        render_annotations(bufnr)

        local still_here = vim.api.nvim_get_current_win() == win
          and vim.api.nvim_win_get_buf(win) == bufnr
          and vim.api.nvim_win_get_cursor(win)[1] == lnum
          and vim.fn.mode() == 'n'
        if still_here then
          show_entry(entry, { focus = false })
        else
          notify(string.format('%s: %s  (<leader>vl to open)', expr, result.type))
        end
      end)
    end)
  end)
end

---Evaluate the expression under the cursor, or the visual selection.
function M.eval()
  evaluate()
end

---Reopen the newest result on the cursor line, or the newest result overall.
function M.last()
  if #entries == 0 then
    notify 'No pseudo-eval results yet'
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  for _, entry in ipairs(entries) do
    if entry.bufnr == bufnr and entry_lnum(entry) == lnum then
      show_entry(entry)
      return
    end
  end
  show_entry(entries[1], { at_cursor = false })
end

function M.history()
  if #entries == 0 then
    notify 'No pseudo-eval results yet'
    return
  end
  vim.ui.select(entries, {
    prompt = 'Pseudo-eval results',
    format_item = function(entry)
      return string.format(
        '%s %s  %s  │ %s:%d  %s',
        PROVENANCE_ICON[entry.result.provenance],
        ellipsize(entry.expr, 40),
        entry.result.type,
        vim.fn.fnamemodify(entry.filename, ':t'),
        entry_lnum(entry) or entry.lnum,
        os.date('%H:%M', entry.timestamp)
      )
    end,
  }, function(entry)
    if entry then
      show_entry(entry, { at_cursor = false })
    end
  end)
end

function M.toggle_annotations()
  M.config.annotate = not M.config.annotate
  local seen = {}
  for _, entry in ipairs(entries) do
    if not seen[entry.bufnr] then
      seen[entry.bufnr] = true
      render_annotations(entry.bufnr)
    end
  end
  notify('Annotations ' .. (M.config.annotate and 'on' or 'off'))
end

function M.clear()
  local bufnr = vim.api.nvim_get_current_buf()
  entries = vim.tbl_filter(function(entry)
    return entry.bufnr ~= bufnr
  end, entries)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---@return string
function M.statusline()
  local n = vim.tbl_count(pending)
  if n == 0 then
    return ''
  end
  return string.format('%s eval%s ', SPINNER[math.floor(vim.uv.hrtime() / 1e8) % #SPINNER + 1], n > 1 and ' ×' .. n or '')
end

---@param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})

  vim.api.nvim_create_user_command('PseudoEval', function(cmd)
    evaluate { expr = cmd.args ~= '' and cmd.args or nil, force = cmd.bang }
  end, { nargs = '?', bang = true, desc = 'Pseudo-evaluate the expression under the cursor (! to re-run)' })
  vim.api.nvim_create_user_command('PseudoEvalLast', M.last, { desc = 'Reopen the latest pseudo-eval result' })
  vim.api.nvim_create_user_command('PseudoEvalHistory', M.history, { desc = 'Browse pseudo-eval results' })
  vim.api.nvim_create_user_command('PseudoEvalToggle', M.toggle_annotations, { desc = 'Toggle pseudo-eval annotations' })
  vim.api.nvim_create_user_command('PseudoEvalClear', M.clear, { desc = 'Clear pseudo-eval results for this buffer' })

  vim.keymap.set({ 'n', 'x' }, '<leader>vv', M.eval, { desc = 'Pseudo-eval: inspect [v]alue' })
  vim.keymap.set('n', '<leader>vl', M.last, { desc = 'Pseudo-eval: [l]ast result' })
  vim.keymap.set('n', '<leader>vh', M.history, { desc = 'Pseudo-eval: [h]istory' })
  vim.keymap.set('n', '<leader>vt', M.toggle_annotations, { desc = 'Pseudo-eval: [t]oggle annotations' })
  vim.keymap.set('n', '<leader>vc', M.clear, { desc = 'Pseudo-eval: [c]lear buffer results' })
end

return M
