local M = {}
local Repo = require 'bookmarks.domain.repo'
local Service = require 'bookmarks.domain.service'

---@class BookmarkWalk.Session
---@field list_id integer
---@field bookmark_id integer?

---@type BookmarkWalk.Session?
local session
local float_win
local float_source
local original_goto

local function notify(message, level)
  vim.notify('Bookmark walk: ' .. message, level or vim.log.levels.WARN)
end

local function close_float()
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    vim.api.nvim_win_close(float_win, true)
  end
  float_win = nil
  float_source = nil
end

local function dismiss_if_changed(event)
  if not float_source then
    return
  end
  if event.event == 'BufLeave' or event.event == 'WinLeave' or event.event == 'InsertEnter' or event.event == 'VimResized' then
    close_float()
    return
  end
  local view = vim.fn.winsaveview()
  if
    vim.api.nvim_get_current_win() ~= float_source.win
    or vim.api.nvim_get_current_buf() ~= float_source.buf
    or not vim.deep_equal(vim.api.nvim_win_get_cursor(0), float_source.cursor)
    or vim.api.nvim_buf_get_changedtick(0) ~= float_source.changedtick
    or view.topline ~= float_source.view.topline
    or view.leftcol ~= float_source.view.leftcol
    or view.skipcol ~= float_source.view.skipcol
  then
    close_float()
  end
end

local function ordered_stops(list)
  local stops = {}
  local function collect(node)
    if node.type == 'bookmark' then
      stops[#stops + 1] = node
      return
    end
    table.sort(node.children, function(a, b)
      if a.order == b.order then
        return a.id < b.id
      end
      return (a.order or 0) < (b.order or 0)
    end)
    for _, child in ipairs(node.children) do
      collect(child)
    end
  end
  collect(list)
  return stops
end

local function current_walk()
  local list = Repo.ensure_and_get_active_list()
  local stops = ordered_stops(list)
  local index
  if session and session.list_id == list.id then
    for i, stop in ipairs(stops) do
      if stop.id == session.bookmark_id then
        index = i
        break
      end
    end
  end
  return list, stops, index
end

local function anchor_error(bookmark)
  local location = bookmark.location
  if not location or not location.line or location.line < 1 then
    return 'This stop has no valid source location.'
  end
  if vim.fn.filereadable(location.path) == 0 then
    return 'Source file is missing or unreadable: ' .. location.path
  end
  local buf = vim.fn.bufadd(location.path)
  vim.fn.bufload(buf)
  local line = vim.api.nvim_buf_get_lines(buf, location.line - 1, location.line, false)[1]
  if line == nil or bookmark.content == nil or line ~= bookmark.content then
    return string.format('Stale anchor at %s:%d. Refresh this bookmark before following it.', location.path, location.line)
  end
end

local function show_float(list, stops, index)
  close_float()
  local bookmark = stops[index]
  local lines = { bookmark.name, '' }
  local description = vim.trim(bookmark.description or '')
  vim.list_extend(lines, vim.split(description ~= '' and description or 'No explanation attached. Use <leader>me to add one.', '\n'))
  local title = string.format(' %s · %d/%d ', list.name, index, #stops)
  local width = math.min(72, vim.o.columns - 4, vim.api.nvim_win_get_width(0) - 4)
  if width < 12 or vim.api.nvim_win_get_height(0) < 5 then
    notify 'Window is too small for the explanation. Enlarge it and press <leader>mw.'
    return
  end
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  height = math.min(height, 12)
  local options = vim.lsp.util.make_floating_popup_options(width, height, {
    border = 'rounded',
    focusable = false,
    title = title,
    title_pos = 'left',
  })
  if options.height < 1 then
    notify 'No space for the explanation. Enlarge the window and press <leader>mw.'
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.b[buf].completion = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  float_source = {
    win = vim.api.nvim_get_current_win(),
    buf = vim.api.nvim_get_current_buf(),
    cursor = vim.api.nvim_win_get_cursor(0),
    changedtick = vim.api.nvim_buf_get_changedtick(0),
    view = vim.fn.winsaveview(),
  }
  float_win = vim.api.nvim_open_win(buf, false, options)
  vim.w[float_win].bookmark_walk = true
  vim.wo[float_win].wrap = true
  vim.wo[float_win].linebreak = true
  vim.wo[float_win].conceallevel = 0
end

local function visit(list, stops, index, opts)
  close_float()
  local bookmark = stops[index]
  local ok, problem = pcall(anchor_error, bookmark)
  if not ok or problem then
    notify(tostring(problem))
    return false
  end
  local opened, result = pcall(original_goto, bookmark.id, opts)
  if not opened then
    notify('Could not open stop: ' .. tostring(result), vim.log.levels.ERROR)
    return false
  end
  session = { list_id = list.id, bookmark_id = bookmark.id }
  show_float(list, stops, index)
  return true, result
end

function M.start(name)
  local list, stops, index = current_walk()
  if name and name ~= '' then
    local found
    for _, candidate in ipairs(Repo.find_lists()) do
      if candidate.name == name then
        found = candidate
        break
      end
    end
    if not found then
      notify('List not found: ' .. name)
      return false
    end
    list = found
    stops = ordered_stops(list)
    index = nil
    if session and session.list_id == list.id then
      for i, stop in ipairs(stops) do
        if stop.id == session.bookmark_id then
          index = i
          break
        end
      end
    end
  end
  if #stops == 0 then
    notify('No bookmarks in ' .. list.name .. '.')
    return false
  end
  local ok = visit(list, stops, index or 1)
  if ok then
    Service.set_active_list(list.id)
    require('bookmarks.sign').safe_refresh_signs()
  end
  return ok
end

function M.stop()
  close_float()
  session = nil
end

function M.step(direction)
  if not session then
    vim.cmd(direction == 1 and 'BookmarksGotoNextInList' or 'BookmarksGotoPrevInList')
    return
  end
  local list, stops, index = current_walk()
  if #stops == 0 then
    M.stop()
    notify 'The active list has no stops. Walk mode ended.'
    return
  end
  local target = index and ((index - 1 + direction) % #stops + 1) or (direction == 1 and 1 or #stops)
  return visit(list, stops, target)
end

function M.toggle()
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    close_float()
  else
    M.start()
  end
end

function M.pick()
  if not session then
    vim.cmd 'BookmarksGoto'
    return
  end
  local list, stops = current_walk()
  local entries = vim.deepcopy(stops)
  for i, stop in ipairs(entries) do
    stop.name = string.format('%d · %s', i, stop.name)
  end
  require('bookmarks.picker').pick_bookmark(function(bookmark)
    if bookmark then
      Service.goto_bookmark(bookmark.id)
    end
  end, { prompt = 'Walk: ' .. list.name, bookmarks = entries, sorting_strategy = 'ascending' })
end

function M.setup()
  if not original_goto then
    original_goto = Service.goto_bookmark
    -- Observe picker and tree jumps too; previews must not advance the walkthrough.
    Service.goto_bookmark = function(id, opts)
      if session and not (opts and (opts.keep_cursor or opts.cmd == 'float')) then
        local list, stops = current_walk()
        for i, stop in ipairs(stops) do
          if stop.id == id then
            local _, result = visit(list, stops, i, opts)
            return result
          end
        end
      end
      return original_goto(id, opts)
    end
  end

  local group = vim.api.nvim_create_augroup('BookmarkWalk', { clear = true })
  vim.api.nvim_create_autocmd(
    { 'CursorMoved', 'CursorMovedI', 'BufLeave', 'WinLeave', 'InsertEnter', 'TextChanged', 'TextChangedI', 'WinScrolled', 'VimResized' },
    {
      group = group,
      callback = dismiss_if_changed,
    }
  )
  vim.api.nvim_create_user_command('BookmarkWalk', function(args)
    M.start(args.args)
  end, {
    nargs = '?',
    desc = 'Start or resume an annotated bookmark walkthrough',
    complete = function(prefix)
      local names = {}
      for _, list in ipairs(Repo.find_lists()) do
        if vim.startswith(list.name, prefix) then
          names[#names + 1] = list.name
        end
      end
      table.sort(names)
      return names
    end,
  })
  vim.api.nvim_create_user_command('BookmarkWalkStop', M.stop, { desc = 'End the bookmark walkthrough' })
  vim.keymap.set('n', '<leader>mn', function()
    M.step(1)
  end, { desc = 'Bookmark next stop' })
  vim.keymap.set('n', '<leader>mp', function()
    M.step(-1)
  end, { desc = 'Bookmark previous stop' })
  vim.keymap.set('n', '<leader>mw', M.toggle, { desc = 'Bookmark walk explanation' })
  vim.keymap.set({ 'n', 'v' }, '<leader>mo', M.pick, { desc = 'Bookmark goto' })
end

return M
