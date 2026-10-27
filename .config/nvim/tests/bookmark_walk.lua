local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(root)
local plugins = vim.fn.stdpath 'data' .. '/lazy-0.12/'
for _, name in ipairs { 'bookmarks.nvim', 'sqlite.lua', 'telescope.nvim', 'plenary.nvim' } do
  vim.opt.rtp:append(plugins .. name)
end

vim.g.mapleader = ' '
vim.o.hidden = true
vim.o.swapfile = false
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
directory = assert(vim.uv.fs_realpath(directory))
vim.cmd 'runtime plugin/bookmarks.lua'
require('bookmarks').setup {
  db_dir = directory,
  calibrate = { auto_calibrate_cur_buf = false },
}
local Repo = require 'bookmarks.domain.repo'
local Node = require 'bookmarks.domain.node'
local Service = require 'bookmarks.domain.service'
local Walk = require 'config.bookmark_walk'

local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end
vim.keymap.set('n', 'K', '<cmd>echo "LSP hover"<cr>')
local hover = vim.fn.maparg('K', 'n')
Walk.setup()

local a = directory .. '/entry.lua'
local b = directory .. '/worker.lua'
local detour = directory .. '/definition.lua'
local source = { 'local M = {}', 'function M.run()', '  dispatch()', 'end', 'return M' }
vim.fn.writefile(source, a)
vim.fn.writefile(source, b)
vim.fn.writefile({ 'local definition = true', 'return definition' }, detour)
local list_id = Repo.insert_node(Node.new_list 'walk-test/ordered')
local ids = {}
for i, location in ipairs {
  { path = a, line = 2, col = 0 },
  { path = b, line = 2, col = 0 },
  { path = a, line = 4, col = 0 },
  { path = b, line = 4, col = 0 },
} do
  local node = Node.new_bookmark('Stop ' .. i, location)
  node.content = source[location.line]
  node.description = 'Explains stop ' .. i .. '.\nNext: follow the next call.'
  node.visited_at = 100
  ids[i] = Repo.insert_node(node, list_id)
end
local order = { ids[3], ids[1], ids[4], ids[2] }
for i, id in ipairs(order) do
  local node = Repo.find_node(id)
  node.order = i - 1
  Repo.update_node(node)
end
Service.set_active_list(list_id)

local function eq(actual, expected)
  assert(vim.deep_equal(actual, expected), 'Expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual))
end

local function floats()
  return vim.tbl_filter(function(win)
    return vim.w[win].bookmark_walk == true
  end, vim.api.nvim_list_wins())
end

local function at(id, position)
  local node = Repo.find_node(id)
  eq(vim.api.nvim_buf_get_name(0), node.location.path)
  eq(vim.api.nvim_win_get_cursor(0), { node.location.line, node.location.col })
  eq(#floats(), 1)
  local window = floats()[1]
  local config = vim.api.nvim_win_get_config(window)
  eq(config.focusable, false)
  local title = vim.inspect(config.title)
  assert(title:find(position .. '/4', 1, true), title)
  local buf = vim.api.nvim_win_get_buf(window)
  eq(vim.bo[buf].modifiable, false)
  assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find(node.description, 1, true))
  assert(not vim.bo.modified)
end

local count = 0
local function test(name, run)
  run()
  count = count + 1
  print('PASS ' .. name)
end

test('start at persisted order, preserve code focus, display the stored explanation', function()
  local win = vim.api.nvim_get_current_win()
  assert(Walk.start 'walk-test/ordered')
  eq(vim.api.nvim_get_current_win(), win)
  at(order[1], 1)
  vim.cmd 'redraw'
  vim.wait(30)
  vim.api.nvim_exec_autocmds('CursorMoved', {})
  vim.api.nvim_exec_autocmds('WinScrolled', { pattern = tostring(win) })
  eq(#floats(), 1)
  eq(vim.fn.maparg('K', 'n'), hover)
end)

test('rapid cross-file stepping and wraparound ignore tied visit timestamps', function()
  for i = 1, 24 do
    assert(Walk.step(1))
    at(order[i % 4 + 1], i % 4 + 1)
  end
  assert(Walk.step(-1))
  at(order[4], 4)
  assert(Walk.step(1))
  at(order[1], 1)
end)

test('LSP-style detour closes the note, resumes the same stop, and retains sequence', function()
  vim.cmd.edit(detour)
  eq(#floats(), 0)
  assert(Walk.start())
  at(order[1], 1)
  vim.cmd.edit(detour)
  assert(Walk.step(1))
  at(order[2], 2)
end)

test('toggle and cursor movement close only the explanation', function()
  Walk.toggle()
  eq(#floats(), 0)
  Walk.toggle()
  at(order[2], 2)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', {})
  eq(#floats(), 0)
  assert(Walk.step(1))
  at(order[3], 3)
end)

test('existing bookmark jump synchronizes the walk index', function()
  Service.goto_bookmark(order[1])
  at(order[1], 1)
  assert(Walk.step(1))
  at(order[2], 2)
end)

test('real Telescope picker selects a numbered stop and continues from there', function()
  Walk.pick()
  assert(
    vim.wait(500, function()
      return vim.bo.filetype == 'TelescopePrompt'
    end),
    'Telescope did not open'
  )
  local prompt = vim.api.nvim_get_current_buf()
  local picker = require('telescope.actions.state').get_current_picker(prompt)
  assert(
    vim.wait(500, function()
      return picker.manager and picker.manager:num_results() == 4
    end),
    'Telescope did not populate'
  )
  picker:set_selection(picker:get_row(3))
  eq(picker:get_selection().value.id, order[3])
  require('telescope.actions').select_default(prompt)
  at(order[3], 3)
  assert(Walk.step(1))
  at(order[4], 4)
end)

test('preview windows do not advance the walkthrough', function()
  local preview = Service.goto_bookmark(order[1], { cmd = 'float', keep_cursor = true })
  assert(vim.api.nvim_win_is_valid(preview))
  vim.api.nvim_win_close(preview, true)
  assert(Walk.step(1))
  at(order[1], 1)
end)

test('stale live buffer anchors warn and do not jump to unrelated code', function()
  local node = Repo.find_node(order[2])
  local buf = vim.fn.bufadd(node.location.path)
  vim.fn.bufload(buf)
  vim.api.nvim_buf_set_lines(buf, node.location.line - 1, node.location.line, false, { 'changed anchor' })
  local before = { vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0) }
  assert(not Walk.step(1))
  eq({ vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0) }, before)
  assert(notifications[#notifications].message:find('Stale anchor', 1, true))
  vim.api.nvim_buf_set_lines(buf, node.location.line - 1, node.location.line, false, { node.content })
  vim.bo[buf].modified = false
  assert(Walk.step(1))
  at(order[2], 2)
end)

test('missing files are reported without creating an empty source buffer', function()
  local node = Repo.find_node(order[3])
  local old_path = node.location.path
  node.location.path = directory .. '/missing.lua'
  Repo.update_node(node)
  assert(not Walk.step(1))
  assert(notifications[#notifications].message:find('missing or unreadable', 1, true))
  eq(vim.fn.bufnr(node.location.path), -1)
  node.location.path = old_path
  Repo.update_node(node)
end)

test('unsaved code is preserved when the next file cannot be opened', function()
  vim.o.hidden = false
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'local unsaved = true' })
  local id = order[3]
  local node = Repo.find_node(id)
  local old_path = node.location.path
  node.location.path = detour
  node.location.line = 1
  node.content = 'local definition = true'
  Repo.update_node(node)
  assert(not Walk.step(1))
  eq(vim.api.nvim_get_current_buf(), buf)
  eq(vim.api.nvim_get_current_line(), source[2])
  eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false), { 'local unsaved = true' })
  assert(notifications[#notifications].message:find('Could not open stop', 1, true))
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { source[1] })
  vim.bo[buf].modified = false
  node.location.path = old_path
  node.location.line = 4
  node.content = source[4]
  Repo.update_node(node)
  vim.o.hidden = true
end)

test('empty and unknown lists leave the existing walk usable', function()
  Repo.insert_node(Node.new_list 'walk-test/empty')
  assert(not Walk.start 'walk-test/empty')
  assert(not Walk.start 'walk-test/unknown')
  assert(Walk.step(1))
  at(order[3], 3)
end)

test('live reordering follows the stored list order while retaining the selected ID', function()
  local node = Repo.find_node(order[2])
  node.order = 10
  Repo.update_node(node)
  Service.goto_bookmark(order[3])
  assert(Walk.step(1))
  at(order[4], 3)
end)

test('switching the active list follows its selected stop', function()
  local other = Repo.insert_node(Node.new_list 'walk-test/other')
  local other_ids = {}
  for i, path in ipairs { a, b } do
    local node = Node.new_bookmark('Other stop ' .. i, { path = path, line = 2, col = 0 })
    node.content = source[2]
    node.description = 'Another trail.\nNext: continue in this list.'
    other_ids[i] = Repo.insert_node(node, other)
  end
  Service.set_active_list(other)
  Service.goto_bookmark(other_ids[2])
  assert(vim.inspect(vim.api.nvim_win_get_config(floats()[1]).title):find('2/2', 1, true))
  assert(Walk.step(1))
  eq(vim.api.nvim_buf_get_name(0), a)
  assert(vim.inspect(vim.api.nvim_win_get_config(floats()[1]).title):find('1/2', 1, true))
  assert(Walk.start 'walk-test/ordered')
  at(order[1], 1)
  Service.goto_bookmark(order[4])
end)

test('missing descriptions and small windows have explicit fallback behavior', function()
  local node = Repo.find_node(order[4])
  local description = node.description
  node.description = ''
  Repo.update_node(node)
  assert(Walk.start())
  local buf = vim.api.nvim_win_get_buf(floats()[1])
  assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('No explanation attached', 1, true))
  node.description = description
  Repo.update_node(node)
  local columns = vim.o.columns
  vim.o.columns = 12
  assert(Walk.start())
  eq(#floats(), 0)
  assert(notifications[#notifications].message:find('too small', 1, true))
  vim.o.columns = columns
  assert(Walk.start())
end)

test('commands, completion, repeated setup, and ordinary bookmark fallback', function()
  Walk.setup()
  assert(vim.tbl_contains(vim.fn.getcompletion('BookmarkWalk walk-test/', 'cmdline'), 'walk-test/ordered'))
  vim.cmd 'BookmarkWalk walk-test/ordered'
  at(order[4], 3)
  vim.cmd 'BookmarkWalkStop'
  eq(#floats(), 0)
  local only = Repo.insert_node(Node.new_list 'walk-test/single')
  local node = Node.new_bookmark('Ordinary bookmark', { path = a, line = 2, col = 0 })
  node.content = source[2]
  Repo.insert_node(node, only)
  Service.set_active_list(only)
  Walk.step(1)
  eq(vim.api.nvim_buf_get_name(0), a)
  eq(vim.api.nvim_win_get_cursor(0)[1], 2)
  eq(#floats(), 0)
  eq(vim.fn.maparg('K', 'n'), hover)
end)

print(string.format('%d bookmark walkthrough checks passed', count))
vim.cmd 'qa!'
