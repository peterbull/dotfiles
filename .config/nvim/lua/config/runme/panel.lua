local M = {}

local ns = vim.api.nvim_create_namespace 'runme_panel'

M.width = 72
M.preview_rows = 12

---@alias runme.StepStatus 'pending'|'running'|'done'|'failed'|'skipped'

---@class runme.Step
---@field text string
---@field status runme.StepStatus
---@field note? string

---@class runme.Result
---@field title string
---@field text? string
---@field columns? string[]
---@field rows? any[][]
---@field query? string
---@field language? 'sql'|'ruby'|'json'|'text'
---@field target? 'local'|'prod'

---@class runme.Approval
---@field id string
---@field title string
---@field message string

---@alias runme.Status 'starting'|'running'|'idle'|'awaiting approval'|'handed off'|'cancelled'|'error'|'exited'

---@class runme.Run
---@field id string
---@field prompt string
---@field mode string
---@field target 'local'|'prod'
---@field file string
---@field line integer
---@field status runme.Status
---@field started integer
---@field plan runme.Step[]
---@field log { id?: string, text: string, state: 'running'|'ok'|'error'|'info' }[]
---@field notes string[]
---@field streaming string
---@field result? runme.Result
---@field approval? runme.Approval
---@field stop? { file: string, line: integer, name?: string }
---@field finished? integer

local STEP_ICON = { pending = '·', running = '⏳', done = '✓', failed = '✗', skipped = '–' }
local LOG_ICON = { running = '▸', ok = '✓', error = '✗', info = '•' }

M.buf = nil ---@type integer|nil
M.on_create = nil ---@type fun(buf: integer)|nil

---@param value any
---@return string
local function cell(value)
  if value == nil or value == vim.NIL then
    return 'NULL'
  end
  return (tostring(value):gsub('[\r\n\t]', ' '))
end

---@param columns string[]
---@param rows any[][]
---@param max_rows? integer
---@param max_width? integer
---@return string[]
function M.table_lines(columns, rows, max_rows, max_width)
  max_width = max_width or 40
  local widths = {}
  for i, name in ipairs(columns) do
    widths[i] = math.min(max_width, vim.fn.strdisplaywidth(name))
  end
  local shown = max_rows and math.min(#rows, max_rows) or #rows
  for r = 1, shown do
    for i = 1, #columns do
      widths[i] = math.min(max_width, math.max(widths[i], vim.fn.strdisplaywidth(cell(rows[r][i]))))
    end
  end
  local function format(values)
    local out = {}
    for i = 1, #columns do
      local text = cell(values[i])
      if vim.fn.strdisplaywidth(text) > widths[i] then
        text = vim.fn.strcharpart(text, 0, widths[i] - 1) .. '…'
      end
      out[i] = text .. string.rep(' ', widths[i] - vim.fn.strdisplaywidth(text))
    end
    return (table.concat(out, ' │ '):gsub('%s+$', ''))
  end
  local lines = { format(columns) }
  local rule = {}
  for i = 1, #columns do
    rule[i] = string.rep('─', widths[i])
  end
  table.insert(lines, table.concat(rule, '─┼─'))
  for r = 1, shown do
    table.insert(lines, format(rows[r]))
  end
  if shown < #rows then
    table.insert(lines, string.format('… %d more rows (o to open all)', #rows - shown))
  end
  return lines
end

---@param text string
---@return string[]
local function split(text)
  return vim.split(text, '\n', { plain = true })
end

---@param run runme.Run
---@return string[] lines, { line: integer, group: string }[] highlights
function M.lines(run)
  local lines, hls = {}, {}
  local function add(text, group)
    for _, line in ipairs(split(text)) do
      table.insert(lines, line)
      if group then
        table.insert(hls, { line = #lines - 1, group = group })
      end
    end
  end
  local function section(name)
    add ''
    add('── ' .. name .. ' ' .. string.rep('─', math.max(0, M.width - #name - 4)), 'Title')
  end

  local elapsed = (run.finished or os.time()) - run.started
  local target_group = run.target == 'prod' and 'DiagnosticError' or 'DiagnosticOk'
  add(string.format('RunMe  %s · %s · %s:%d', run.mode, run.target, vim.fn.fnamemodify(run.file, ':~:.'), run.line), target_group)
  add(string.format('[%s  %d:%02d]  %s', run.status, math.floor(elapsed / 60), elapsed % 60, run.prompt), 'Comment')

  if run.approval then
    section 'Approval needed'
    add(run.approval.title, 'DiagnosticWarn')
    add(run.approval.message)
    add('a approve · n decline', 'DiagnosticWarn')
  end

  if run.stop then
    section 'Stopped'
    add(string.format('⏸ %s:%d %s', vim.fn.fnamemodify(run.stop.file or '?', ':~:.'), run.stop.line or 0, run.stop.name or ''), 'DiagnosticWarn')
  end

  if #run.plan > 0 then
    section 'Plan'
    for i, step in ipairs(run.plan) do
      local note = step.note and ('  — ' .. step.note) or ''
      local group = step.status == 'failed' and 'DiagnosticError' or step.status == 'done' and 'DiagnosticOk' or nil
      add(string.format(' %d. %s %s%s', i, STEP_ICON[step.status] or '·', step.text, note), group)
    end
  end

  if run.result then
    local result = run.result
    section('Result: ' .. result.title)
    if result.text and result.text ~= '' then
      add(result.text)
    end
    if result.columns and result.rows then
      add(string.format('%d row(s)', #result.rows), 'Comment')
      for _, line in ipairs(M.table_lines(result.columns, result.rows, M.preview_rows, 24)) do
        add(line)
      end
    end
    if result.query then
      add('e edit & re-run · o open full · y yank', 'Comment')
    end
  end

  local notes = vim.list_extend(vim.list_slice(run.notes), run.streaming ~= '' and { run.streaming } or {})
  if #notes > 0 then
    section 'Agent'
    for _, note in ipairs(notes) do
      add(note)
    end
  end

  if #run.log > 0 then
    section 'Log'
    for _, entry in ipairs(run.log) do
      local group = entry.state == 'error' and 'DiagnosticError' or 'Comment'
      add(string.format('%s %s', LOG_ICON[entry.state], entry.text), group)
    end
  end

  add ''
  add('a/n approve · i follow-up · x cancel · r rerun · gd jump · d dap-ui · q close · ? help', 'NonText')
  return lines, hls
end

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.buf, 'runme://panel')
  vim.bo[M.buf].buftype = 'nofile'
  vim.bo[M.buf].bufhidden = 'hide'
  vim.bo[M.buf].swapfile = false
  vim.bo[M.buf].filetype = 'runme'
  vim.b[M.buf].completion = false
  if M.on_create then
    M.on_create(M.buf)
  end
  return M.buf
end

---@return integer|nil
function M.win()
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == M.buf then
      return win
    end
  end
  return nil
end

---@param focus boolean
---@return integer win
function M.open(focus)
  local buf = M.ensure_buf()
  local win = M.win()
  if not win then
    local current = vim.api.nvim_get_current_win()
    win = vim.api.nvim_open_win(buf, focus, { split = 'right', win = -1, width = M.width })
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].winfixwidth = true
    vim.wo[win].winfixbuf = true
    vim.wo[win].cursorline = false
    vim.wo[win].list = false
    if not focus and vim.api.nvim_win_is_valid(current) then
      vim.api.nvim_set_current_win(current)
    end
  elseif focus then
    vim.api.nvim_set_current_win(win)
  end
  return win
end

function M.close()
  local win = M.win()
  if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then
    vim.api.nvim_win_close(win, true)
  end
end

---@param run runme.Run
function M.render(run)
  local buf = M.ensure_buf()
  local lines, hls = M.lines(run)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, hl.line, 0, { line_hl_group = hl.group })
  end
end

---@param result runme.Result
function M.open_result(result)
  local lines
  if result.columns and result.rows then
    lines = M.table_lines(result.columns, result.rows, nil, 80)
  else
    lines = split(result.text or '')
  end
  if result.query then
    local header = { '-- ' .. result.title .. ' (' .. (result.target or 'local') .. ')' }
    for _, line in ipairs(split(result.query)) do
      table.insert(header, '-- ' .. line)
    end
    table.insert(header, '')
    lines = vim.list_extend(header, lines)
  end
  vim.cmd 'botright new'
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'runme-result'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.wo.wrap = false
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, nowait = true })
end

return M
