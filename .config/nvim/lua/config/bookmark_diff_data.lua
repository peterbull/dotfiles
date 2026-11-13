local M = {}

---@class BookmarkDiff.Anchor
---@field path string
---@field line integer
---@field end_line integer
---@field lines string[]
---@field context_before string[]
---@field context_after string[]
---@field fingerprint string

---@class BookmarkDiff.Comparison
---@field version integer
---@field repo string
---@field base {ref: string, sha: string}
---@field target {kind: 'worktree'|'commit', ref?: string, sha?: string}

local function rows(sql, params)
  local db = require('bookmarks.domain.repo')._DB
  local result = db:with_open(function()
    return db:eval(sql, params)
  end)
  return type(result) == 'table' and result or {}
end

local function metadata(table_name, key, id)
  if #rows('SELECT name FROM sqlite_master WHERE type = :type AND name = :name', { type = 'table', name = table_name }) == 0 then
    return nil
  end
  local row = rows('SELECT * FROM ' .. table_name .. ' WHERE ' .. key .. ' = :id', { id = id })[1]
  if row then
    local data = vim.json.decode(row.data)
    assert(data.version == 1, 'Unsupported bookmark diff metadata version.')
    return data, row.list_id
  end
end

function M.comparison(list_id)
  return metadata('bookmark_walk_lists', 'list_id', list_id)
end

function M.anchors(bookmark_id)
  return metadata('bookmark_walk_stops', 'bookmark_id', bookmark_id)
end

local function git(repo, args)
  local command = { 'git', '-C', repo, '--literal-pathspecs' }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait(10000)
  assert(result.code == 0, 'Could not read comparison: ' .. vim.trim(result.stderr or 'git failed'))
  return result.stdout
end

function M.path(repo, path)
  assert(type(path) == 'string' and path ~= '' and not path:find('\0', 1, true), 'Invalid diff path.')
  assert(not vim.startswith(path, '/') and not vim.tbl_contains(vim.split(path, '/', { plain = true }), '..'), 'Diff paths must stay within the repository.')
  return repo .. '/' .. path
end

local function lines(text)
  assert(not text:find('\0', 1, true), 'Binary files cannot be diff walkthrough stops.')
  local result = vim.split(text, '\n', { plain = true })
  if #result > 1 and result[#result] == '' then
    table.remove(result)
  end
  for i, line in ipairs(result) do
    result[i] = line:gsub('\r$', '')
  end
  return result
end

local function revision(repo, sha, path)
  M.path(repo, path)
  assert(type(sha) == 'string' and sha:match '^%x+$' and (#sha == 40 or #sha == 64), 'Comparison must use a full commit SHA.')
  local entry = git(repo, { 'ls-tree', '-z', sha, '--', path })
  if entry == '' then
    return nil
  end
  local oid = entry:match '^100%d%d%d blob (%x+)\t'
  assert(oid, 'Diff stops require regular files: ' .. path)
  return lines(git(repo, { 'cat-file', 'blob', oid }))
end

function M.live(repo, path)
  local full = M.path(repo, path)
  local stat = vim.uv.fs_lstat(full)
  if stat then
    local canonical = assert(vim.uv.fs_realpath(full))
    assert(stat.type == 'file' and vim.startswith(canonical, repo .. '/'), 'Diff stops require regular files within the repository: ' .. path)
  end
  local buf = vim.fn.bufnr(full)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    assert(vim.bo[buf].buftype == '', 'The current side must be a normal file buffer.')
    local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, line in ipairs(result) do
      assert(not line:find('\0', 1, true) and not line:find('\n', 1, true), 'Binary files cannot be diff walkthrough stops.')
    end
    return result
  end
  if not stat then
    return nil
  end
  local result = vim.fn.readfile(full)
  if #result == 0 then
    result = { '' }
  end
  for i, line in ipairs(result) do
    assert(not line:find('\n', 1, true), 'Binary files cannot be diff walkthrough stops.')
    result[i] = line:gsub('\r$', '')
  end
  return result
end

function M.resolve(anchor, source)
  assert(source, 'Stale anchor: file is absent: ' .. anchor.path)
  assert(type(anchor.lines) == 'table' and #anchor.lines > 0 and anchor.end_line - anchor.line + 1 == #anchor.lines, 'Invalid diff anchor range.')
  if vim.fn.sha256(table.concat(source, '\n')) == anchor.fingerprint then
    assert(vim.deep_equal(vim.list_slice(source, anchor.line, anchor.end_line), anchor.lines), 'Stale anchor: ' .. anchor.path)
    return { line = anchor.line, end_line = anchor.end_line }
  end
  local context = vim.deepcopy(anchor.context_before)
  vim.list_extend(context, anchor.lines)
  vim.list_extend(context, anchor.context_after)
  local found
  for start = 1, #source - #context + 1 do
    if vim.deep_equal(vim.list_slice(source, start, start + #context - 1), context) then
      assert(not found, 'Stale anchor: context is ambiguous: ' .. anchor.path .. '. Refresh this stop.')
      found = start + #anchor.context_before
    end
  end
  assert(found, 'Stale anchor: explained code or context changed: ' .. anchor.path .. '. Refresh this stop.')
  return { line = found, end_line = found + #anchor.lines - 1 }
end

function M.prepare(list_id, stops)
  local comparison = assert(M.comparison(list_id), 'This list has no comparison. Configure it with nvim_bookmarks first.')
  assert(comparison.target.kind == 'worktree' or comparison.target.kind == 'commit', 'Invalid comparison target.')
  assert(vim.uv.fs_realpath(comparison.repo) == comparison.repo, 'Comparison repository is missing or has moved.')
  local prepared = { comparison = comparison, stops = {}, files = {}, before = {}, after = {} }
  local seen = {}
  for _, stop in ipairs(stops) do
    local anchors, owner = M.anchors(stop.id)
    assert(anchors and owner == list_id, 'Stop #' .. stop.id .. ' has no anchors for this comparison.')
    assert(anchors.before or anchors.after, 'A diff stop needs at least one anchor.')
    local path = (anchors.after or anchors.before).path
    local oldpath = (anchors.before or anchors.after).path
    local pair = oldpath .. '\0' .. path
    assert(not seen[path] or seen[path] == pair, 'A current path cannot refer to several previous files: ' .. path)
    if not seen[path] then
      seen[path] = pair
      prepared.before[oldpath] = revision(comparison.repo, comparison.base.sha, oldpath)
      prepared.after[path] = comparison.target.kind == 'worktree' and M.live(comparison.repo, path)
        or comparison.target.kind == 'commit' and revision(comparison.repo, comparison.target.sha, path)
        or nil
      local before, after = prepared.before[oldpath], prepared.after[path]
      prepared.files[#prepared.files + 1] = {
        path = path,
        oldpath = oldpath ~= path and oldpath or nil,
        status = not before and 'A' or not after and 'D' or oldpath ~= path and 'R' or 'M',
        before_absent = before == nil,
        after_absent = after == nil,
      }
    end
    prepared.stops[stop.id] = { anchors = anchors, path = path, oldpath = oldpath }
  end
  return prepared
end

function M.validate(prepared, bookmark_id)
  local stop = assert(prepared.stops[bookmark_id], 'Stop is absent from this comparison.')
  local comparison = prepared.comparison
  local before = prepared.before[stop.oldpath]
  local after = prepared.after[stop.path]
  if comparison.target.kind == 'worktree' then
    after = M.live(comparison.repo, stop.path)
  end
  local result = { path = stop.path }
  if stop.anchors.before then
    result.before = M.resolve(stop.anchors.before, before)
  end
  if stop.anchors.after then
    result.after = M.resolve(stop.anchors.after, after)
  end
  local target = stop.anchors.target_without_anchor
  if target then
    if target.absent then
      assert(after == nil, 'Stale anchor: the removed file exists again: ' .. stop.path .. '. Refresh this stop.')
    else
      assert(
        after and vim.fn.sha256(table.concat(after, '\n')) == target.fingerprint,
        'Stale anchor: the current side of this deletion changed: ' .. stop.path .. '. Refresh this stop.'
      )
    end
  end
  result.focus = result.after and 'b' or 'a'
  return result
end

return M
