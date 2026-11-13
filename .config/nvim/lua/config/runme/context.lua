local M = {}

---@alias runme.QueryKind 'ar'|'sql'|'es'|'redis'|'selection'

---@class runme.Query
---@field kind runme.QueryKind
---@field text string
---@field start_line integer
---@field end_line integer

---@class runme.Symbol
---@field name string
---@field path string
---@field start_line integer
---@field end_line integer

---@class runme.DapState
---@field attached boolean
---@field port? integer
---@field adapter? string
---@field stopped boolean
---@field frame? { file: string, line: integer, name: string }
---@field breakpoints integer

---@class runme.Context
---@field file string
---@field filetype string
---@field root string
---@field project 'phonetrac'|'generic'
---@field cursor_line integer
---@field symbol? runme.Symbol
---@field query? runme.Query
---@field dap runme.DapState
---@field text string

M.context_lines = 80

local FUNCTION_TYPES = {
  method = true,
  singleton_method = true,
  function_definition = true,
  function_declaration = true,
  function_item = true,
  method_definition = true,
  method_declaration = true,
  local_function = true,
  ['function'] = true,
  arrow_function = true,
}

local CONTAINER_TYPES = {
  class = true,
  module = true,
  class_definition = true,
  class_declaration = true,
  impl_item = true,
}

local STATEMENT_STOPS = {
  body_statement = true,
  block_body = true,
  program = true,
  method = true,
  singleton_method = true,
  block = true,
  do_block = true,
  ['then'] = true,
  ['else'] = true,
}

local AR_PATTERN = {
  '%.where%f[^%w_]',
  '%.joins%f[^%w_]',
  '%.left_joins%f[^%w_]',
  '%.includes%f[^%w_]',
  '%.find_by%f[^%w_]',
  '%.find_by_sql%f[^%w_]',
  '%.pluck%f[^%w_]',
  '%.order%f[^%w_]',
  '%.group%f[^%w_]',
  '%.limit%f[^%w_]',
  '%.count%f[^%w_]',
  '%.exists%?',
  '%.find_each%f[^%w_]',
  '%.select_all%f[^%w_]',
  '%.select_value%f[^%w_]',
  '%.select_rows%f[^%w_]',
}

local SQL_START = { 'select', 'with', 'update', 'insert', 'delete', 'explain' }

---@param text string
---@return boolean
local function looks_like_sql(text)
  local head = text:lower():gsub('^%s*%%[qw]?[%(%[{<|!]', ''):gsub('^[^%a]*', '')
  for _, word in ipairs(SQL_START) do
    if head:sub(1, #word + 1):match('^' .. word .. '%f[^%a]') then
      return true
    end
  end
  return false
end

---@param text string
---@return runme.QueryKind|nil
function M.classify(text)
  if text:find('RDSC', 1, true) or text:find '%f[%w_]redis%f[^%w_]' then
    return 'redis'
  end
  if text:find '%.search%f[^%w_]' and text:find('query:', 1, true) then
    return 'es'
  end
  for _, pattern in ipairs(AR_PATTERN) do
    if text:find(pattern) then
      return 'ar'
    end
  end
  if looks_like_sql(text) then
    return 'sql'
  end
  return nil
end

---@param node TSNode
---@param bufnr integer
---@return string|nil
local function node_name(node, bufnr)
  local name = node:field('name')[1]
  if name then
    return vim.treesitter.get_node_text(name, bufnr)
  end
  return nil
end

---@param bufnr integer
---@param row integer 1-based
---@param col integer 0-based
---@return TSNode|nil
local function node_at(bufnr, row, col)
  local parser = vim.treesitter.get_parser(bufnr, nil, { error = false })
  if not parser then
    return nil
  end
  parser:parse()
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row - 1, col }, ignore_injections = false })
  if ok then
    return node
  end
  return nil
end

---@param bufnr integer
---@param node TSNode|nil
---@return runme.Symbol|nil
local function enclosing_symbol(bufnr, node)
  local fn, containers = nil, {}
  while node do
    local kind = node:type()
    if not fn and FUNCTION_TYPES[kind] then
      fn = node
    elseif CONTAINER_TYPES[kind] then
      table.insert(containers, 1, node_name(node, bufnr) or kind)
    end
    node = node:parent()
  end
  if not fn then
    return nil
  end
  local name = node_name(fn, bufnr) or fn:type()
  local start_row, _, end_row = fn:range()
  local sep = fn:type() == 'singleton_method' and '.' or '#'
  local path = #containers > 0 and (table.concat(containers, '::') .. sep .. name) or name
  return { name = name, path = path, start_line = start_row + 1, end_line = end_row + 1 }
end

---@param bufnr integer
---@param node TSNode|nil
---@return runme.Query|nil
local function query_from_tree(bufnr, node)
  local outer_call, string_node
  while node and not STATEMENT_STOPS[node:type()] do
    local kind = node:type()
    if kind == 'call' or kind == 'call_expression' or kind == 'method_invocation' then
      outer_call = node
    elseif not string_node and (kind == 'string' or kind == 'heredoc_body' or kind == 'string_content' or kind == 'template_string') then
      string_node = node
    end
    node = node:parent()
  end
  if string_node then
    local text = vim.treesitter.get_node_text(string_node, bufnr)
    if looks_like_sql(text) then
      local s, _, e = string_node:range()
      return { kind = 'sql', text = text, start_line = s + 1, end_line = e + 1 }
    end
  end
  if outer_call then
    local text = vim.treesitter.get_node_text(outer_call, bufnr)
    local kind = M.classify(text)
    if kind then
      local s, _, e = outer_call:range()
      return { kind = kind, text = text, start_line = s + 1, end_line = e + 1 }
    end
  end
  return nil
end

---@param bufnr integer
---@param row integer
---@return runme.Query|nil
local function sql_paragraph(bufnr, row)
  local last = vim.api.nvim_buf_line_count(bufnr)
  local first_row, last_row = row, row
  local function blank(r)
    return vim.trim(vim.api.nvim_buf_get_lines(bufnr, r - 1, r, false)[1] or '') == ''
  end
  if blank(row) then
    return nil
  end
  while first_row > 1 and not blank(first_row - 1) do
    first_row = first_row - 1
  end
  while last_row < last and not blank(last_row + 1) do
    last_row = last_row + 1
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, first_row - 1, last_row, false), '\n')
  return { kind = 'sql', text = text, start_line = first_row, end_line = last_row }
end

---@return runme.DapState
function M.dap_state()
  local state = { attached = false, stopped = false, breakpoints = 0 }
  local dap = package.loaded['dap']
  if not dap then
    return state
  end
  for _, bps in pairs(require('dap.breakpoints').get()) do
    state.breakpoints = state.breakpoints + #bps
  end
  local session = dap.session()
  if not session then
    return state
  end
  state.attached = true
  state.port = tonumber(session.config.port)
  state.adapter = session.config.type
  state.stopped = session.stopped_thread_id ~= nil
  local frame = session.current_frame
  if state.stopped and frame and frame.source then
    state.frame = { file = frame.source.path or frame.source.name, line = frame.line, name = frame.name }
  end
  return state
end

---@param path string
---@return string
function M.project_root(path)
  if path == '' then
    return vim.uv.cwd() --[[@as string]]
  end
  return vim.fs.root(path, { '.git' }) or vim.fs.dirname(path)
end

---@param root string
---@return 'phonetrac'|'generic'
local function project_profile(root)
  if vim.uv.fs_stat(root .. '/bin/query') and vim.uv.fs_stat(root .. '/config/application.rb') then
    return 'phonetrac'
  end
  return 'generic'
end

---@param ctx runme.Context
---@param lines string[]
---@param start_row integer
local function render(ctx, lines, start_row)
  local parts = {
    string.format('File: %s (%s)', ctx.file, ctx.filetype ~= '' and ctx.filetype or 'none'),
    string.format('Project root: %s (profile: %s)', ctx.root, ctx.project),
    'Cursor: line ' .. ctx.cursor_line,
  }
  if ctx.symbol then
    table.insert(parts, string.format('Enclosing symbol: %s (lines %d-%d)', ctx.symbol.path, ctx.symbol.start_line, ctx.symbol.end_line))
  end
  if ctx.query then
    table.insert(parts, string.format('Detected %s query (lines %d-%d):', ctx.query.kind, ctx.query.start_line, ctx.query.end_line))
    table.insert(parts, '```')
    table.insert(parts, ctx.query.text)
    table.insert(parts, '```')
  end
  local dap = ctx.dap
  if dap.attached then
    table.insert(
      parts,
      string.format(
        'Debugger: attached (%s, port %s)%s; %d breakpoints',
        dap.adapter or '?',
        dap.port or '?',
        dap.frame and string.format(', stopped at %s:%d', dap.frame.file, dap.frame.line) or '',
        dap.breakpoints
      )
    )
  else
    table.insert(parts, string.format('Debugger: not attached; %d breakpoints', dap.breakpoints))
  end
  table.insert(parts, '')
  for i, line in ipairs(lines) do
    local lnum = start_row + i - 1
    table.insert(parts, string.format('%s%-5d %s', lnum == ctx.cursor_line and '>' or ' ', lnum, line))
  end
  return table.concat(parts, '\n')
end

---@param opts? { win?: integer, selection?: { start_line: integer, end_line: integer } }
---@return runme.Context
function M.capture(opts)
  opts = opts or {}
  local win = opts.win or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1], cursor[2]
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = M.project_root(file)
  local filetype = vim.bo[bufnr].filetype

  local indent = (vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''):find '%S'
  local node = node_at(bufnr, row, indent and math.max(col, indent - 1) or col)
  local query
  if opts.selection then
    local s, e = opts.selection.start_line, opts.selection.end_line
    local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false), '\n')
    query = { kind = M.classify(text) or 'selection', text = text, start_line = s, end_line = e }
  elseif filetype == 'sql' or filetype == 'mysql' then
    query = sql_paragraph(bufnr, row)
  else
    query = query_from_tree(bufnr, node)
  end

  local count = vim.api.nvim_buf_line_count(bufnr)
  local start_row = math.max(1, row - M.context_lines)
  local end_row = math.min(count, row + M.context_lines)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

  ---@type runme.Context
  local ctx = {
    file = file,
    filetype = filetype,
    root = root,
    project = project_profile(root),
    cursor_line = row,
    symbol = enclosing_symbol(bufnr, node),
    query = query,
    dap = M.dap_state(),
    text = '',
  }
  ctx.text = render(ctx, lines, start_row)
  return ctx
end

---@param ctx runme.Context
---@return table
function M.public(ctx)
  return {
    file = ctx.file,
    filetype = ctx.filetype,
    root = ctx.root,
    project = ctx.project,
    cursor_line = ctx.cursor_line,
    symbol = ctx.symbol,
    query = ctx.query,
    dap = ctx.dap,
  }
end

return M
