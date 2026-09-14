local M = {}

M.config = {
  context_lines = 200,
  pi_timeout = 120000,
  history_file = vim.fn.stdpath 'data' .. '/helpme_history.json',
  history_limit = 50,
}

local SYSTEM_PROMPT = [[You are a concise programming assistant embedded in a code editor.
Answer in exactly ONE sentence. Be pithy, direct, and technical.
No explanations, no preamble, no code blocks unless needed to answer the question.
The user is editing the code shown in context and needs a quick answer.
]]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

---Project root of the current buffer, so pi can grep the whole codebase.
---@return string
local function project_root()
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then
    return vim.uv.cwd()
  end
  return vim.fs.root(path, { '.git' }) or vim.fs.dirname(path)
end

---Run pi as a brief one-off session in the project root and return the answer.
---pi greps/reads the codebase itself; context here is just the cursor neighborhood.
---@param question string
---@param context { text: string }
---@param callback fun(answer: string|nil, err: string|nil)
local function ask_pi(question, context, callback)
  local prompt = SYSTEM_PROMPT
    .. 'You may use your tools (bash, read) to search the codebase for the answer. '
    .. 'Never edit or write files.\n\n'
    .. context.text
    .. '\n\nQuestion: '
    .. question

  local args = {
    'pi',
    '-p',
    '--no-session',
    '--no-extensions',
    '--no-skills',
    '--no-prompt-templates',
    '--no-themes',
    '--exclude-tools',
    'edit,write',
    prompt,
  }

  local timer = vim.uv.new_timer()
  local proc = vim.system(args, { cwd = project_root(), text = true }, function(obj)
    if timer then
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
    end
    if obj.code ~= 0 then
      callback(nil, vim.trim(obj.stderr ~= '' and obj.stderr or ('pi exited ' .. tostring(obj.code))))
      return
    end
    callback(vim.trim(obj.stdout))
  end)

  -- pi runs tools, so it can take a while — but never hang the popup forever
  timer:start(M.config.pi_timeout, 0, function()
    proc:kill 'sigterm'
  end)
end

---Wrap text to fit within max_width characters per line.
---Breaks at word boundaries when possible.
---@param text string
---@param max_width number
---@return string[]
local function wrap_text(text, max_width)
  if max_width < 1 then
    return { text }
  end
  local lines = {}
  for raw_line in text:gmatch '[^\n]*' do
    local line = raw_line
    while #line > max_width do
      local chunk = line:sub(1, max_width)
      -- Walk backwards to find a space boundary
      local break_at = nil
      for i = max_width, 1, -1 do
        if chunk:sub(i, i) == ' ' then
          break_at = i
          break
        end
      end
      if break_at then
        table.insert(lines, chunk:sub(1, break_at - 1))
        line = line:sub(break_at + 1)
      else
        -- No space — hard break at max_width
        table.insert(lines, chunk)
        line = line:sub(max_width + 1)
      end
    end
    if #line > 0 then
      table.insert(lines, line)
    end
  end
  return lines
end

---Read the persisted history file.
---@return table[]
local function load_history()
  local f = io.open(M.config.history_file, 'r')
  if not f then
    return {}
  end
  local content = f:read '*a'
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == 'table' then
    return data
  end
  return {}
end

---Ensure the history directory exists (safe at module load, NOT in fast event context).
local function ensure_history_dir()
  local dir = vim.fn.fnamemodify(M.config.history_file, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
end

---Persist history to disk. Avoids vim.fn calls so it is safe in fast event context.
---@param history table[]
local function save_history(history)
  local f = io.open(M.config.history_file, 'w')
  if not f then
    return
  end
  f:write(vim.json.encode(history))
  f:close()
end

---Append a Q&A entry at the front of history and trim to limit.
---@param entry table
local function add_history_entry(entry)
  local history = load_history()
  table.insert(history, 1, entry)
  if #history > M.config.history_limit then
    history = vim.list_slice(history, 1, M.config.history_limit)
  end
  save_history(history)
end

---@param bufnr number
local function no_completion(bufnr)
  vim.b[bufnr].completion = false -- blink.cmp
  vim.bo[bufnr].completefunc = ''
  vim.bo[bufnr].omnifunc = ''
  vim.bo[bufnr].complete = ''
end

---Map q / <Esc> to close this popup by window handle, so it quits even if focus
---lands elsewhere. Normal + insert mode.
---@param bufnr number
---@param winnr number
local function map_quit(bufnr, winnr)
  local function close()
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
  end
  vim.keymap.set('n', 'q', close, { buffer = bufnr, nowait = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = bufnr, nowait = true })
  vim.keymap.set('i', '<Esc>', close, { buffer = bufnr, nowait = true })
end

---Truncate a string for display, adding ellipsis if cut.
---@param s string
---@param max_len number
---@return string
local function ellipsize(s, max_len)
  s = s:gsub('\n', ' ')
  if #s <= max_len then
    return s
  end
  return s:sub(1, max_len - 1) .. '…'
end

----------------------------------------------------------------------
-- Context capture
----------------------------------------------------------------------

---Capture surrounding lines, cursor position, and file metadata.
---@return { text: string, filetype: string, filename: string, cursor_line: number }
function M.capture_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local ft = vim.bo[bufnr].filetype
  local filename = vim.fn.expand '%:p'

  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_row = math.max(1, row - M.config.context_lines)
  local end_row = math.min(buf_line_count, row + M.config.context_lines)

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

  local parts = {
    'File: ' .. filename .. ' (' .. (ft ~= '' and ft or 'none') .. ')',
    'Cursor: line ' .. row,
    '',
  }

  for i, line in ipairs(lines) do
    local lnum = start_row + i - 1
    local cursor_mark = lnum == row and '>' or ' '
    table.insert(parts, string.format('%s%-4d %s', cursor_mark, lnum, line))
  end

  return {
    text = table.concat(parts, '\n'),
    filetype = ft,
    filename = filename,
    cursor_line = row,
  }
end

----------------------------------------------------------------------
-- Response display popup
----------------------------------------------------------------------

---Open a popup displaying the answer.
---@param answer string
local function show_response_popup(answer)
  local popup_width = math.floor(math.min(vim.o.columns * 0.6, 80))
  local margin = 2
  local text_width = popup_width - margin * 2
  local wrapped = wrap_text(answer, text_width)

  local height = math.min(#wrapped + 2, math.floor(vim.o.lines * 0.5))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, wrapped)
  vim.bo[buf].modifiable = false
  no_completion(buf)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = popup_width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - popup_width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Answer ',
    title_pos = 'center',
  })

  vim.cmd 'stopinsert' -- land in the answer popup in normal mode (came from typing)

  vim.wo[win].wrap = false -- we already hard-wrapped
  vim.wo[win].cursorline = false

  map_quit(buf, win)
  vim.keymap.set('n', 'y', function()
    vim.fn.setreg('+', answer)
    vim.notify('Answer yanked to clipboard', vim.log.levels.INFO)
  end, { buffer = buf, nowait = true, desc = 'Yank answer' })
  vim.keymap.set('n', 'h', function()
    vim.cmd 'close'
    M.show_history()
  end, { buffer = buf, nowait = true, desc = 'View history' })
end

----------------------------------------------------------------------
-- History viewer
----------------------------------------------------------------------

---Open a popup listing past Q&A entries.
function M.show_history()
  local history = load_history()

  if #history == 0 then
    vim.notify('No helpme history yet', vim.log.levels.INFO)
    return
  end

  local lines = {}
  for i, entry in ipairs(history) do
    local date = os.date('%m-%d %H:%M', entry.timestamp)
    local q = ellipsize(entry.question, 45)
    local a = ellipsize(entry.answer, 30)
    table.insert(lines, string.format('%2d. %s  %-45s │ %s', i, date, q, a))
  end

  local width = math.min(100, vim.o.columns - 4)
  local height = math.min(#lines + 2, 20)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  no_completion(buf)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' HelpMe History (' .. #history .. ') ',
    title_pos = 'center',
  })

  vim.wo[win].cursorline = true

  -- Press Enter on a row to view it in full
  vim.keymap.set('n', '<CR>', function()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local entry = history[idx]
    if entry then
      vim.cmd 'close'
      show_response_popup(entry.answer)
    end
  end, { buffer = buf, nowait = true, desc = 'View full answer' })

  map_quit(buf, win)
  vim.keymap.set('n', 'd', function()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    if idx >= 1 and idx <= #history then
      table.remove(history, idx)
      save_history(history)
      vim.cmd 'close'
      M.show_history()
    end
  end, { buffer = buf, nowait = true, desc = 'Delete entry' })
end

----------------------------------------------------------------------
-- Main entry point: ask a question
----------------------------------------------------------------------

---Open the quick-question popup. When the user submits, capture context,
---call the LLM, and display the answer.
function M.show()
  -- snapshot context before we open the popup (so cursor is correct)
  local context = M.capture_context()

  local prompt_width = math.floor(math.min(vim.o.columns * 0.5, 70))
  local prompt_height = 3
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype = 'prompt'
  vim.bo[prompt_buf].bufhidden = 'wipe'
  -- No LSP here — disable all autocomplete in the prompt window
  no_completion(prompt_buf)

  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = 'editor',
    width = prompt_width,
    height = prompt_height,
    row = math.floor((vim.o.lines - prompt_height) / 2),
    col = math.floor((vim.o.columns - prompt_width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Quick Question ',
    title_pos = 'center',
  })

  vim.fn.prompt_setprompt(prompt_buf, '> ')

  -- Helper to force-close the prompt window without save prompts
  local function close_prompt()
    if vim.api.nvim_win_is_valid(prompt_win) then
      vim.api.nvim_win_close(prompt_win, true)
    end
  end

  vim.fn.prompt_setcallback(prompt_buf, function(question)
    vim.schedule(function()
      question = vim.trim(question)
      if question == '' then
        close_prompt()
        return
      end

      -- Replace prompt buffer with "Thinking..." text
      vim.bo[prompt_buf].buftype = 'nofile'
      vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { '  Thinking…' })
      vim.bo[prompt_buf].modifiable = false

      ask_pi(question, context, function(answer, err)
        vim.schedule(function()
          if err then
            -- Show the error in the prompt popup
            vim.bo[prompt_buf].modifiable = true
            local error_text = 'Error: ' .. err
            vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, wrap_text(error_text, prompt_width - 4))
            vim.bo[prompt_buf].modifiable = false
            vim.keymap.set('n', 'q', close_prompt, { buffer = prompt_buf, nowait = true })
            vim.keymap.set('n', '<Esc>', close_prompt, { buffer = prompt_buf, nowait = true })
            return
          end

          -- Save to history
          add_history_entry {
            question = question,
            answer = answer,
            filetype = context.filetype,
            filename = context.filename,
            cursor_line = context.cursor_line,
            timestamp = os.time(),
          }

          -- Close the prompt popup and open the response popup
          close_prompt()
          show_response_popup(answer)
        end)
      end)
    end)
  end)

  -- Close keymaps for the prompt buffer (normal + insert modes)
  vim.keymap.set('n', 'q', close_prompt, { buffer = prompt_buf, nowait = true })
  vim.keymap.set('n', '<Esc>', close_prompt, { buffer = prompt_buf, nowait = true })
  vim.keymap.set('i', '<Esc>', close_prompt, { buffer = prompt_buf, nowait = true })
  vim.keymap.set('i', '<C-c>', close_prompt, { buffer = prompt_buf, nowait = true })

  -- Start in insert mode so user can type immediately
  vim.cmd 'startinsert'
end

----------------------------------------------------------------------
-- User commands
----------------------------------------------------------------------

vim.api.nvim_create_user_command('HelpMe', function()
  M.show()
end, { desc = 'Ask a quick programming question to the LLM' })

vim.api.nvim_create_user_command('HelpMeHistory', function()
  M.show_history()
end, { desc = 'Browse previous helpme Q&A history' })

----------------------------------------------------------------------
-- Initialisation
----------------------------------------------------------------------

ensure_history_dir()

return M
