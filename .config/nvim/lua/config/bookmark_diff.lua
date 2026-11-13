local M = {}
local Data = require 'config.bookmark_diff_data'
local namespace = vim.api.nvim_create_namespace 'BookmarkDiffWalk'
local active

local function clear_ranges(state)
  for _, buf in ipairs(state.highlighted or {}) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    end
  end
  state.highlighted = {}
end

function M.current()
  return active
end

function M.validate_selected()
  local state = assert(active, 'There is no active diff walk.')
  local selected = assert(state.selected, 'There is no selected diff stop.')
  return Data.validate(state.prepared, selected.bookmark_id)
end

function M.inside()
  if not active or not active.view.tabpage or not vim.api.nvim_tabpage_is_valid(active.view.tabpage) then
    return false
  end
  if vim.api.nvim_get_current_tabpage() ~= active.view.tabpage then
    return false
  end
  local layout = active.view.cur_layout
  local win = vim.api.nvim_get_current_win()
  if layout then
    for _, pane in ipairs { layout.a, layout.b } do
      if pane.id == win and pane.file.bufnr == vim.api.nvim_get_current_buf() then
        return true
      end
    end
  end
  return false
end

function M.close()
  local state = active
  if not state then
    return
  end
  active = nil
  state.pending = nil
  clear_ranges(state)
  if state.view.tabpage and vim.api.nvim_tabpage_is_valid(state.view.tabpage) then
    state.view:close()
    require('diffview.lib').dispose_view(state.view)
  end
end

local function highlight(state, pane, range, move)
  if not range then
    return
  end
  local buf = vim.api.nvim_win_get_buf(pane.id)
  for line = range.line, range.end_line do
    vim.api.nvim_buf_set_extmark(buf, namespace, line - 1, 0, {
      line_hl_group = 'Visual',
      priority = 150,
    })
  end
  state.highlighted[#state.highlighted + 1] = buf
  if move then
    vim.api.nvim_win_set_cursor(pane.id, { range.line, 0 })
  end
end

local function finish(state, entry)
  if active ~= state or not vim.api.nvim_tabpage_is_valid(state.view.tabpage) then
    return
  end
  local pending = state.pending
  local selected = pending or state.selected
  if not selected then
    state.loading = false
    return
  end
  if entry.path ~= selected.range.path then
    if pending then
      state.view:set_file_by_path(pending.range.path, false)
    else
      state.loading = false
    end
    return
  end
  state.pending = nil
  state.loading = false
  if vim.api.nvim_get_current_tabpage() ~= state.view.tabpage then
    return
  end
  local ok, problem = pcall(function()
    local range = Data.validate(state.prepared, selected.bookmark_id)
    local layout = state.view.cur_layout
    assert(layout.a and layout.b, 'The diff walk needs a two-pane layout.')
    vim.wo[layout.a.id].wrap = false
    vim.wo[layout.b.id].wrap = false
    clear_ranges(state)
    highlight(state, layout.a, range.before, pending ~= nil)
    highlight(state, layout.b, range.after, pending ~= nil)
    if pending then
      vim.api.nvim_set_current_win(layout[range.focus].id)
      vim.cmd 'normal! zvzt'
    end
    local comparison = state.prepared.comparison
    local oldpath = state.prepared.stops[selected.bookmark_id].oldpath
    local before_label = state.prepared.before[oldpath] and comparison.base.sha:sub(1, 10) or 'FILE ABSENT · ' .. comparison.base.sha:sub(1, 10)
    vim.wo[layout.a.id].winbar = ' BEFORE · ' .. before_label .. ' · %<' .. oldpath:gsub('%%', '%%%%')
    local label = comparison.target.kind == 'worktree' and 'WORKING BUFFER' or comparison.target.sha:sub(1, 10)
    if not state.prepared.after[range.path] then
      label = 'FILE DELETED · ' .. label
    end
    vim.wo[layout.b.id].winbar = ' CURRENT · ' .. label .. ' · %<' .. range.path:gsub('%%', '%%%%')
  end)
  if ok then
    state.selected = selected
    if pending then
      pending.done()
    end
  else
    state.selected = nil
    selected.done(tostring(problem))
  end
end

local function create(list_id, prepared)
  require 'diffview'
  local CDiffView = require('diffview.api.views.diff.diff_view').CDiffView
  local GitRev = require('diffview.vcs.adapters.git.rev').GitRev
  local RevType = require('diffview.vcs.rev').RevType
  local comparison = prepared.comparison
  local files = { working = prepared.files }
  local right = comparison.target.kind == 'worktree' and GitRev(RevType.LOCAL) or GitRev(RevType.COMMIT, comparison.target.sha)
  local view = CDiffView {
    git_root = comparison.repo,
    left = GitRev(RevType.COMMIT, comparison.base.sha),
    right = right,
    files = files,
    update_files = function()
      return files
    end,
    get_file_data = function(_, path, side)
      return assert(prepared[side == 'left' and 'before' or 'after'][path], 'Missing comparison contents: ' .. path)
    end,
  }
  assert(view.valid, 'Could not create a Diffview for this repository.')
  view.bookmark_walk_owned = true
  local state = { view = view, list_id = list_id, prepared = prepared, highlighted = {}, loading = false }
  active = state
  local function configure_entry(entry)
    local file = vim.iter(prepared.files):find(function(item)
      return item.path == entry.path
    end)
    entry.layout.a.file.nulled = file.before_absent
    entry.layout.b.file.nulled = file.after_absent
    entry.layout.a.file.binary = false
    entry.layout.b.file.binary = false
    entry.layout.a.file.winopts.wrap = false
    entry.layout.b.file.winopts.wrap = false
  end
  for _, entry in view.files:iter() do
    configure_entry(entry)
  end
  local create_entries = view.create_file_entries
  view.create_file_entries = function(self, data)
    local entries = create_entries(self, data)
    for _, section in pairs(entries) do
      for _, entry in ipairs(section) do
        configure_entry(entry)
      end
    end
    return entries
  end
  view.emitter:on('post_layout', function()
    view.cur_layout:open_null()
    view.panel:close()
  end)
  view.emitter:on(
    'file_open_post',
    vim.schedule_wrap(function(_, entry)
      finish(state, entry)
    end)
  )
  view.emitter:on('file_open_pre', function(_, entry)
    state.loading = true
    clear_ranges(state)
    local refreshing = not state.pending and state.selected and entry.path == state.selected.range.path
    if not refreshing and state.dismiss then
      state.dismiss()
    end
  end)
  view.emitter:on('view_closed', function()
    clear_ranges(state)
    state.pending = nil
    if active == state then
      active = nil
    end
  end)
  require('diffview.lib').add_view(view)
  local ok, problem = pcall(view.open, view)
  if not ok then
    if view.commit_log_panel then
      view:close()
    else
      require('diffview.scene.views.standard.standard_view').StandardView.close(view)
    end
    require('diffview.lib').dispose_view(view)
    active = nil
    error(problem)
  end
  return state
end

function M.visit(list, stops, bookmark_id, done, dismiss)
  local comparison = assert(Data.comparison(list.id), 'This list has no comparison. Configure it with nvim_bookmarks first.')
  local signature = table.concat({ comparison.repo, comparison.base.sha, comparison.target.kind, comparison.target.sha or '' }, '\0')
  local ids = table.concat(
    vim.tbl_map(function(stop)
      return tostring(stop.id)
    end, stops),
    ','
  )
  local state = active
  local anchors, owner = Data.anchors(bookmark_id)
  assert(owner == list.id, 'This stop was moved out of its comparison.')
  local cached = state and state.prepared.stops[bookmark_id]
  local changed_anchors = cached and not vim.deep_equal(cached.anchors, anchors)
  if
    not state
    or state.list_id ~= list.id
    or state.signature ~= signature
    or state.ids ~= ids
    or changed_anchors
    or not vim.api.nvim_tabpage_is_valid(state.view.tabpage)
  then
    local prepared = Data.prepare(list.id, stops)
    Data.validate(prepared, bookmark_id)
    M.close()
    state = create(list.id, prepared)
    state.signature, state.ids = signature, ids
  else
    state.prepared.stops[bookmark_id].anchors = anchors
  end
  local range = Data.validate(state.prepared, bookmark_id)
  state.dismiss = dismiss
  vim.api.nvim_set_current_tabpage(state.view.tabpage)
  state.pending = { bookmark_id = bookmark_id, range = range, done = done }
  if not state.loading then
    state.loading = true
    state.view:set_file_by_path(range.path, false)
  end
  local pending = state.pending
  vim.defer_fn(function()
    if active == state and state.pending == pending then
      state.pending = nil
      state.loading = false
      done 'Timed out opening the diff stop. Resume the walk to retry.'
    end
  end, 5000)
end

return M
