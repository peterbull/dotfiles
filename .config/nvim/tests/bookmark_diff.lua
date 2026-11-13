local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(root)
local plugins = vim.fn.stdpath 'data' .. '/lazy-0.12/'
for _, name in ipairs { 'bookmarks.nvim', 'sqlite.lua', 'telescope.nvim', 'plenary.nvim', 'diffview.nvim' } do
  vim.opt.rtp:append(plugins .. name)
end
local fixture = vim.json.decode(table.concat(vim.fn.readfile(assert(vim.env.BOOKMARK_DIFF_FIXTURE)), '\n'))
vim.g.mapleader = ' '
vim.g.have_nerd_font = false
vim.o.hidden = true
vim.o.swapfile = false
vim.o.columns = 160
vim.o.lines = 45
vim.cmd.cd(fixture.repo)
vim.cmd 'runtime plugin/bookmarks.lua'
require('bookmarks').setup { db_dir = fixture.directory, calibrate = { auto_calibrate_cur_buf = false } }
vim.cmd 'runtime plugin/diffview.lua'
dofile(root .. '/lua/plugins/git.lua')[1].config()
local Repo = require 'bookmarks.domain.repo'
local Service = require 'bookmarks.domain.service'
local Walk = require 'config.bookmark_walk'
local Diff = require 'config.bookmark_diff'
local Data = require 'config.bookmark_diff_data'
local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end
Walk.setup()
local original_tab = vim.api.nvim_get_current_tabpage()
vim.cmd.edit(fixture.repo .. '/context.lua')
vim.cmd('DiffviewOpen ' .. fixture.base)
local unrelated = require('diffview.lib').get_current_view()
assert(vim.wait(3000, function()
  return unrelated.cur_entry ~= nil
end))
vim.api.nvim_set_current_tabpage(original_tab)

local function eq(actual, expected)
  assert(vim.deep_equal(actual, expected), 'Expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual))
end
local function floats()
  return vim.tbl_filter(function(win)
    return vim.w[win].bookmark_walk == true
  end, vim.api.nvim_list_wins())
end
local function at(position, side, line)
  local expected = position .. '/6'
  assert(
    vim.wait(4000, function()
      local wins = floats()
      return #wins == 1 and vim.inspect(vim.api.nvim_win_get_config(wins[1]).title):find(expected, 1, true)
    end, 10),
    'Stop did not open: ' .. expected .. '\n' .. vim.inspect(notifications)
  )
  local state = assert(Diff.current())
  local layout = state.view.cur_layout
  eq(vim.api.nvim_get_current_win(), layout[side or 'b'].id)
  eq(vim.api.nvim_win_get_cursor(0)[1], line)
  eq(vim.api.nvim_win_get_config(floats()[1]).focusable, false)
  assert(vim.wo[layout.a.id].diff and vim.wo[layout.b.id].diff)
  assert(not vim.wo[layout.a.id].wrap and not vim.wo[layout.b.id].wrap)
  return state, layout
end
local count = 0
local function test(name, run)
  run()
  count = count + 1
  print('PASS ' .. name)
end

test('open the persisted comparison with old and current ranges and a nonfocusable explanation', function()
  assert(Walk.start('example/live', { diff = true }), vim.inspect(notifications))
  local state, layout = at(1, 'b', 3)
  eq(state.view.left.commit, fixture.base)
  eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(layout.a.id), 2, 3, false), { '  dispatch()' })
  eq(vim.api.nvim_get_current_line(), '  enqueue()')
  eq(vim.api.nvim_buf_get_name(0), fixture.repo .. '/change.lua')
  assert(vim.wo[layout.a.id].winbar:find(fixture.base:sub(1, 10), 1, true))
  local marks = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace 'BookmarkDiffWalk', 0, -1, {})
  eq(#marks, 1)
end)

test('switching panes retains the explanation and code focus', function()
  local layout = Diff.current().view.cur_layout
  vim.api.nvim_set_current_win(layout.a.id)
  vim.wait(30)
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = vim.api.nvim_get_current_buf() })
  eq(#floats(), 1)
  eq(vim.api.nvim_get_current_win(), layout.a.id)
  vim.api.nvim_set_current_win(layout.b.id)
  vim.wait(30)
  eq(#floats(), 1)
end)

test('background Diffview refresh retains the explanation, highlights, and pane focus', function()
  local state = Diff.current()
  local layout = state.view.cur_layout
  vim.api.nvim_set_current_win(layout.a.id)
  local refreshed = false
  state.view.emitter:on('file_open_post', function()
    vim.schedule(function()
      refreshed = true
    end)
  end)
  state.view:update_files()
  assert(vim.wait(3000, function()
    return refreshed
  end))
  eq(#floats(), 1)
  eq(vim.api.nvim_get_current_win(), state.view.cur_layout.a.id)
  local buf = vim.api.nvim_win_get_buf(state.view.cur_layout.b.id)
  eq(#vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace 'BookmarkDiffWalk', 0, -1, {}), 1)
  assert(Walk.start())
  at(1, 'b', 3)
end)

test('deleted, renamed, unchanged context, and untracked files use the correct sides', function()
  assert(Walk.step(1))
  local _, layout = at(2, 'a', 2)
  eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(layout.b.id), 0, -1, false), { '' })
  eq(vim.fn.bufnr(fixture.repo .. '/gone.lua'), -1)
  assert(Walk.step(1))
  local state = at(3, 'b', 3)
  eq(state.view.cur_entry.oldpath, 'old.lua')
  assert(Walk.step(1))
  at(4, 'b', 2)
  assert(Walk.step(1))
  at(5, 'b', 1)
  eq(vim.api.nvim_get_current_line(), 'local added = true')
  assert(Walk.step(1))
  at(6, 'b', 5)
  assert(Walk.step(1))
  at(1, 'b', 3)
end)

test('rapid navigation during refresh and same-file stops settle on the latest request', function()
  Diff.current().view:update_files()
  for _ = 1, 24 do
    assert(Walk.step(1))
  end
  at(1, 'b', 3)
  assert(Walk.step(-1))
  at(6, 'b', 5)
  assert(Walk.step(1))
  at(1, 'b', 3)
  eq(#vim.api.nvim_list_tabpages(), 3)
end)

test('detours hide the note and resume the same comparison and selected stop', function()
  local tab = Diff.current().view.tabpage
  vim.api.nvim_set_current_tabpage(original_tab)
  vim.wait(30)
  eq(#floats(), 0)
  assert(Walk.start())
  at(1, 'b', 3)
  eq(Diff.current().view.tabpage, tab)
  Walk.toggle()
  eq(#floats(), 0)
  Walk.toggle()
  at(1, 'b', 3)
end)

test('manual file browsing and same-window code detours dismiss the old explanation', function()
  local state = Diff.current()
  state.view:set_file_by_path('context.lua', true)
  assert(vim.wait(2000, function()
    return state.view.cur_entry.path == 'context.lua' and #floats() == 0
  end))
  assert(Walk.start())
  at(1, 'b', 3)
  vim.cmd.edit(fixture.repo .. '/context.lua')
  vim.wait(30)
  eq(#floats(), 0)
  assert(Walk.start())
  at(1, 'b', 3)
end)

test('deletion notes become stale if the removed file reappears', function()
  vim.fn.writefile({ 'local restored = true' }, fixture.repo .. '/gone.lua')
  local prepared = Data.prepare(fixture.liveId, Repo.find_node(fixture.liveId).children)
  local ok, problem = pcall(Data.validate, prepared, fixture.stopIds[2])
  assert(not ok and tostring(problem):find('removed file exists again', 1, true))
  assert(vim.uv.fs_rename(fixture.repo .. '/gone.lua', fixture.directory .. '/restored.lua'))
end)

test('deletion notes also verify the remaining current file when no after anchor is supplied', function()
  local prepared = Data.prepare(fixture.liveId, Repo.find_node(fixture.liveId).children)
  prepared.stops[fixture.stopIds[1]].anchors = fixture.partialDeletion
  Data.validate(prepared, fixture.stopIds[1])
  local buf = vim.fn.bufnr(fixture.repo .. '/change.lua')
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { '  dispatch()' })
  local ok, problem = pcall(Data.validate, prepared, fixture.stopIds[1])
  assert(not ok and tostring(problem):find('current side of this deletion changed', 1, true))
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { '  enqueue()' })
  vim.bo[buf].modified = false
end)

test('uniquely matching context relocates an anchor after unrelated unsaved edits', function()
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'local prepended = true' })
  assert(Walk.start())
  at(1, 'b', 4)
  assert(vim.bo.modified)
  local anchor = Data.anchors(fixture.stopIds[1]).after
  local context = vim.deepcopy(anchor.context_before)
  vim.list_extend(context, anchor.lines)
  vim.list_extend(context, anchor.context_after)
  local repeated = vim.deepcopy(context)
  vim.list_extend(repeated, context)
  local ok, problem = pcall(Data.resolve, anchor, repeated)
  assert(not ok and tostring(problem):find('ambiguous', 1, true))
end)

test('changed explained code refuses navigation and hides the outdated note', function()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { '  something_else()' })
  vim.api.nvim_exec_autocmds('TextChanged', {})
  eq(#floats(), 0)
  assert(not Walk.start())
  eq(vim.api.nvim_get_current_buf(), buf)
  eq(vim.api.nvim_win_get_cursor(0), cursor)
  assert(notifications[#notifications].message:find('Stale anchor', 1, true))
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { '  enqueue()' })
  assert(Walk.start())
  at(1, 'b', 4)
end)

test('native bookmark selection synchronizes the diff walk and persisted reordering', function()
  Service.goto_bookmark(fixture.stopIds[3])
  at(3, 'b', 3)
  local node = Repo.find_node(fixture.stopIds[6])
  local order = node.order
  node.order = -1
  Repo.update_node(node)
  Service.goto_bookmark(fixture.stopIds[1])
  at(2, 'b', 4)
  assert(Walk.step(-1))
  at(1, 'b', 6)
  node.order = order
  Repo.update_node(node)
end)

test('the numbered Telescope picker follows its selected diff stop', function()
  Walk.pick()
  assert(vim.wait(1000, function()
    return vim.bo.filetype == 'TelescopePrompt'
  end))
  local prompt = vim.api.nvim_get_current_buf()
  local picker = require('telescope.actions.state').get_current_picker(prompt)
  assert(vim.wait(1000, function()
    return picker.manager and picker.manager:num_results() == 6
  end))
  eq(picker:get_selection().value.id, fixture.stopIds[6])
  picker:set_selection(picker:get_row(4))
  eq(picker:get_selection().value.id, fixture.stopIds[4])
  require('telescope.actions').select_default(prompt)
  at(4, 'b', 2)
end)

test('pinned commit views survive the existing HEAD-to-worktree hook and preserve unsaved buffers', function()
  local live_buf = vim.fn.bufnr(fixture.repo .. '/change.lua')
  vim.g.diffview_iadd = { toplevel = fixture.repo, files = { "new file's.lua" } }
  assert(Walk.start 'example/saved')
  assert(vim.wait(4000, function()
    return #floats() == 1
  end))
  local state = Diff.current()
  eq(state.view.right.commit, fixture.head)
  assert(vim.api.nvim_buf_get_name(0):find('diffview://', 1, true))
  eq(vim.api.nvim_win_get_cursor(0)[1], 3)
  eq(vim.api.nvim_get_current_line(), '  enqueue()')
  assert(vim.bo[live_buf].modified)
  Walk.stop()
  eq(#floats(), 0)
  assert(vim.api.nvim_tabpage_is_valid(unrelated.tabpage))
  eq(#vim.api.nvim_list_tabpages(), 2)
  assert(vim.g.diffview_iadd ~= nil)
  vim.g.diffview_iadd = nil
  eq(vim.api.nvim_buf_get_lines(live_buf, 0, 1, false), { 'local prepended = true' })
  assert(vim.bo[live_buf].modified)
end)

test('command entry and native bookmark entry both reopen the saved diff list', function()
  vim.cmd 'BookmarkWalkDiff example/live'
  at(1, 'b', 4)
  Walk.stop()
  Service.goto_bookmark(fixture.stopIds[2])
  at(2, 'a', 2)
  Walk.stop()
  assert(not Walk.start('example/source', { diff = true }))
end)

io.stdout:write(string.format('%d bookmark diff checks passed\n', count))
if vim.env.BOOKMARK_DIFF_RESULT then
  vim.fn.writefile({ string.format('%d bookmark diff checks passed', count) }, vim.env.BOOKMARK_DIFF_RESULT)
end
vim.cmd 'qa!'
