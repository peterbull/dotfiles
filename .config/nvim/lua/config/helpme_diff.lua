-- HelpMeDiff: ask pi for a change, review it as a live diff, accept or reject.
--
-- Flow:
--   1. Snapshot the current buffer, write a scratch copy to a temp file.
--   2. Show that scratch copy in a right-hand split, in diff mode against the
--      real buffer (so the diff starts empty and lights up as pi edits it).
--   3. Run pi against the scratch copy with its edit tool, polling the file so
--      the diff updates live while pi works.
--   4. You accept/reject hunks with native diff keys, or bulk with A / R.
--
-- The real file is never touched until you accept something, and accepted
-- changes land in the real buffer as ordinary (undoable) edits.

local M = {}

M.config = {
  pi_timeout = 180000,
  poll_ms = 400,
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function notify(msg, level)
  vim.notify('HelpMeDiff: ' .. msg, level or vim.log.levels.INFO)
end

---@param path string
---@return string
local function project_root_for(path)
  return vim.fs.root(path, { '.git' }) or vim.fs.dirname(path) or vim.uv.cwd()
end

---Write lines to a file with a trailing newline (unless the list is empty).
---@param path string
---@param lines string[]
local function write_lines(path, lines)
  local f = assert(io.open(path, 'w'))
  if #lines > 0 then
    f:write(table.concat(lines, '\n') .. '\n')
  end
  f:close()
end

---@param path string
---@return string[]|nil
local function read_lines(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local content = f:read '*a'
  f:close()
  local lines = vim.split(content, '\n', { plain = true })
  if lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

---@param lines string[]
---@return string
local function as_text(lines)
  return table.concat(lines, '\n')
end

---Does the buffer's text match what is currently on disk?
---@param buf number
---@param path string
---@return boolean
local function content_matches_disk(buf, path)
  local disk = read_lines(path)
  if not disk then
    return false
  end
  return as_text(disk) == as_text(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

---Number of hunks between two versions of a file.
---@param a string[]
---@param b string[]
---@return number
local function count_hunks(a, b)
  if as_text(a) == as_text(b) then
    return 0
  end
  local ok, hunks = pcall(vim.diff, as_text(a), as_text(b), { result_type = 'indices' })
  if ok and type(hunks) == 'table' then
    return #hunks
  end
  return 1
end

---Last visual selection in the current buffer, if it isn't the whole file.
---@return { l1: number, l2: number, text: string }|nil
local function snapshot_selection()
  local l1 = vim.fn.line "'<"
  local l2 = vim.fn.line "'>"
  if l1 < 1 or l2 < 1 then
    return nil
  end
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local total = vim.api.nvim_buf_line_count(0)
  if l1 == 1 and l2 == total then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  return { l1 = l1, l2 = l2, text = table.concat(lines, '\n') }
end

---Poll a file's mtime and call on_change whenever it moves.
---Returns a stop function.
---@param path string
---@param on_change fun()
---@return fun()
local function watch_file(path, on_change)
  local uv = vim.uv or vim.loop
  local timer = uv.new_timer()
  local last = nil
  local function mtime()
    local st = uv.fs_stat(path)
    return st and (st.mtime.sec * 1e9 + st.mtime.nsec) or nil
  end
  last = mtime()
  timer:start(
    0,
    M.config.poll_ms,
    vim.schedule_wrap(function()
      local now = mtime()
      if now ~= nil and now ~= last then
        last = now
        on_change()
      end
    end)
  )
  return function()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
end

---Prompt popup, HelpMe style. Calls on_submit only for non-empty input.
---@param title string
---@param on_submit fun(text: string)
local function prompt_user(title, on_submit)
  local width = math.floor(math.min(vim.o.columns * 0.6, 80))
  local height = 3
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'prompt'
  vim.bo[buf].bufhidden = 'wipe'
  -- no completion plugins in here
  vim.b[buf].completion = false
  vim.bo[buf].completefunc = ''
  vim.bo[buf].omnifunc = ''
  vim.bo[buf].complete = ''

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.fn.prompt_setprompt(buf, '> ')
  vim.fn.prompt_setcallback(buf, function(text)
    vim.schedule(function()
      text = vim.trim(text)
      close()
      if text ~= '' then
        on_submit(text)
      end
    end)
  end)

  vim.keymap.set('n', 'q', close, { buffer = buf, nowait = true })
  vim.keymap.set({ 'n', 'i' }, '<Esc>', close, { buffer = buf, nowait = true })
  vim.keymap.set('i', '<C-c>', close, { buffer = buf, nowait = true })

  vim.cmd 'startinsert'
end

----------------------------------------------------------------------
-- Review session
----------------------------------------------------------------------

---Open the scratch copy in a right-hand split, diffed against the real buffer.
---@param real_win number
---@param scratch_path string
---@return number scratch_win
local function open_scratch_split(real_win, scratch_path)
  vim.cmd('botright vsplit ' .. vim.fn.fnameescape(scratch_path))
  local scratch_win = vim.api.nvim_get_current_win()
  vim.cmd 'diffthis'
  vim.api.nvim_win_call(real_win, function()
    vim.cmd 'diffthis'
  end)
  return scratch_win
end

---@param buf number
---@param streaming boolean
---@param hunks number
local function set_statusline(buf, streaming, hunks)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end
  if streaming then
    vim.wo[win].winbar = ' HelpMeDiff ⟳ applying… '
  else
    vim.wo[win].winbar = string.format(' HelpMeDiff · %d hunk(s) · A accept all · R reject all · q finish ', hunks)
  end
end

---Build the pi prompt for a single focused edit.
---@param real_path string
---@param scratch_path string
---@param cursor_line number
---@param selection { l1: number, l2: number, text: string }|nil
---@param instruction string
---@return string
local function build_prompt(real_path, scratch_path, cursor_line, selection, instruction)
  local parts = {
    'You are applying one focused code change to one file.',
    '',
    'Real file:           ' .. real_path,
    'Scratch copy to edit: ' .. scratch_path,
    'The scratch copy is byte-identical to the real file.',
    '',
    'Apply the requested change to the scratch copy using your edit tool.',
    'Edit ONLY ' .. scratch_path .. '. Do not create, delete, or modify any other file.',
    'Read the scratch copy yourself before editing; the hints below are only context.',
    '',
    'Cursor line: ' .. cursor_line,
  }
  if selection then
    parts[#parts + 1] = 'Selected range (lines ' .. selection.l1 .. '-' .. selection.l2 .. '):'
    parts[#parts + 1] = selection.text
  end
  parts[#parts + 1] = ''
  parts[#parts + 1] = 'Requested change: ' .. instruction
  return table.concat(parts, '\n')
end

---Run a full review session. Snapshots are taken by the caller.
---@param real_buf number
---@param real_path string
---@param real_win number
---@param cursor_line number
---@param selection { l1: number, l2: number, text: string }|nil
---@param instruction string
function M.run(real_buf, real_path, real_win, cursor_line, selection, instruction)
  local cwd = project_root_for(real_path)
  local original = vim.api.nvim_buf_get_lines(real_buf, 0, -1, false)

  -- scratch copy in the original file's directory is unnecessary; /tmp is fine
  local ext = vim.fn.fnamemodify(real_path, ':e')
  local scratch_path = vim.fn.tempname() .. (ext ~= '' and ('.' .. ext) or '')
  write_lines(scratch_path, original)

  local scratch_win = open_scratch_split(real_win, scratch_path)
  local scratch_buf = vim.api.nvim_get_current_buf()
  vim.bo[scratch_buf].bufhidden = 'wipe'
  if vim.bo[scratch_buf].filetype == '' and vim.bo[real_buf].filetype ~= '' then
    vim.bo[scratch_buf].filetype = vim.bo[real_buf].filetype
  end

  local streamed_lines = original
  local stop_watch = nil
  local timer = nil
  local proc = nil
  local pi_done = false
  local timed_out = false
  local finished = false

  local function reload()
    if not vim.api.nvim_buf_is_valid(scratch_buf) then
      return
    end
    local lines = read_lines(scratch_path)
    if not lines then
      return
    end
    streamed_lines = lines
    vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, lines)
    vim.bo[scratch_buf].modified = false
  end

  local function finish()
    if finished then
      return
    end
    finished = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if stop_watch then
      stop_watch()
    end
    if proc and not pi_done then
      pcall(function()
        proc:kill 'sigterm'
      end)
    end
    for _, w in ipairs { real_win, scratch_win } do
      if vim.api.nvim_win_is_valid(w) then
        vim.api.nvim_win_call(w, function()
          if vim.wo.diff then
            vim.cmd 'diffoff'
          end
        end)
      end
    end
    if vim.api.nvim_win_is_valid(scratch_win) then
      vim.api.nvim_win_close(scratch_win, true)
    end
    if vim.api.nvim_buf_is_valid(scratch_buf) then
      vim.api.nvim_buf_delete(scratch_buf, { force = true })
    end
    pcall(os.remove, scratch_path)
    if vim.api.nvim_win_is_valid(real_win) then
      vim.api.nvim_set_current_win(real_win)
    end
  end

  local function accept_all()
    local lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
    vim.api.nvim_buf_set_lines(real_buf, 0, -1, false, lines) -- one undo step
    notify(string.format('accepted all %d hunk(s) — :w to save', count_hunks(original, lines)))
    finish()
  end

  local function reject_all()
    vim.api.nvim_buf_set_lines(real_buf, 0, -1, false, original)
    if content_matches_disk(real_buf, real_path) then
      vim.bo[real_buf].modified = false
    end
    notify 'rejected all changes'
    finish()
  end

  ---@param summary string
  local function finalize(summary)
    if finished then
      return -- user already closed the review while pi was still running
    end
    reload()
    local hunks = count_hunks(original, streamed_lines)
    if hunks == 0 then
      notify('pi proposed no changes' .. (summary ~= '' and (': ' .. summary) or ''), vim.log.levels.WARN)
      finish()
      return
    end
    notify(
      string.format(
        '%d hunk(s) proposed. Here: A accept all, R reject all, q finish. Left (real) window: ]c / [c navigate, do accept hunk, dp reject hunk.',
        hunks
      )
    )
    set_statusline(scratch_buf, false, hunks)

    local opts = { buffer = scratch_buf, nowait = true }
    vim.keymap.set('n', 'A', accept_all, vim.tbl_extend('force', opts, { desc = 'Accept all changes' }))
    vim.keymap.set('n', 'R', reject_all, vim.tbl_extend('force', opts, { desc = 'Reject all changes' }))
    vim.keymap.set('n', 'q', finish, vim.tbl_extend('force', opts, { desc = 'Finish review' }))
    vim.keymap.set('n', '<Esc>', finish, opts)
  end

  -- if the user closes the scratch window by hand, clean up after them
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = scratch_buf,
    once = true,
    callback = function()
      vim.schedule(finish)
    end,
  })

  stop_watch = watch_file(scratch_path, reload)
  set_statusline(scratch_buf, true, 0)

  local prompt = build_prompt(real_path, scratch_path, cursor_line, selection, instruction)
  local args = {
    'pi',
    '-p',
    '--no-session',
    '--no-extensions',
    '--no-skills',
    '--no-prompt-templates',
    '--no-themes',
    prompt,
  }

  proc = vim.system(args, { cwd = cwd, text = true }, function(obj)
    -- fast event context: uv-only cleanup here, everything else is scheduled
    pi_done = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if stop_watch then
      stop_watch()
    end
    vim.schedule(function()
      if finished then
        return -- user closed the review; nothing to report
      end
      local summary = ''
      if obj.code ~= 0 then
        if timed_out then
          notify(string.format('pi timed out after %ds and was killed', M.config.pi_timeout / 1000), vim.log.levels.WARN)
        else
          notify('pi failed: ' .. vim.trim(obj.stderr ~= '' and obj.stderr or ('exit ' .. obj.code)), vim.log.levels.ERROR)
        end
      else
        summary = vim.trim(obj.stdout):gsub('\n.*', '')
      end
      finalize(summary)
    end)
  end)

  timer = vim.uv.new_timer()
  timer:start(M.config.pi_timeout, 0, function()
    if not pi_done and proc then
      timed_out = true
      pcall(function()
        proc:kill 'sigterm'
      end)
    end
  end)
end

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

function M.show()
  local real_buf = vim.api.nvim_get_current_buf()
  local real_path = vim.api.nvim_buf_get_name(real_buf)

  if real_path == '' or vim.fn.filereadable(real_path) == 0 then
    notify('current buffer is not a saved file', vim.log.levels.WARN)
    return
  end
  if vim.bo[real_buf].buftype ~= '' then
    notify('current buffer is not a normal file buffer', vim.log.levels.WARN)
    return
  end

  local real_win = vim.api.nvim_get_current_win()
  local cursor_line = vim.api.nvim_win_get_cursor(real_win)[1]
  local selection = snapshot_selection()

  prompt_user(' What should change? ', function(instruction)
    M.run(real_buf, real_path, real_win, cursor_line, selection, instruction)
  end)
end

----------------------------------------------------------------------
-- User commands
----------------------------------------------------------------------

vim.api.nvim_create_user_command('HelpMeDiff', function()
  M.show()
end, { desc = 'Ask pi for a change and review it as a diff' })

return M
