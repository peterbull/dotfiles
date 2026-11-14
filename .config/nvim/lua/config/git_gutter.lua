local M = {}
local pending = {}

function M.toggle_pr()
  local buf = vim.api.nvim_get_current_buf()
  local status = vim.b[buf].gitsigns_status_dict
  if not status or not status.root then
    vim.notify('Git gutter: this file is not attached to Gitsigns', vim.log.levels.WARN)
    return
  end
  if pending[buf] then
    vim.notify('Git gutter: loading PR base')
    return
  end
  pending[buf] = true

  local function fail(message)
    pending[buf] = nil
    vim.notify('Git gutter: ' .. message, vim.log.levels.ERROR)
  end

  local function change_base(base, label)
    if not vim.api.nvim_buf_is_valid(buf) then
      pending[buf] = nil
      return
    end
    vim.api.nvim_buf_call(buf, function()
      require('gitsigns').change_base(base, false, function(err)
        pending[buf] = nil
        if err then
          fail(err)
          return
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].gitsigns_pr_base = base
          vim.notify('Git gutter: ' .. label)
        end
      end)
    end)
  end

  if vim.b[buf].gitsigns_pr_base then
    change_base(nil, 'local edits')
    return
  end

  local function run(argv, callback)
    local ok, err = pcall(vim.system, argv, { cwd = status.root, text = true, timeout = 15000 }, vim.schedule_wrap(function(result)
      if not vim.api.nvim_buf_is_valid(buf) then
        pending[buf] = nil
        return
      end
      if result.code ~= 0 then
        fail(argv[1] .. ' failed: ' .. vim.trim(result.stderr or result.stdout or ''))
        return
      end
      callback(vim.trim(result.stdout or ''))
    end))
    if not ok then
      fail(tostring(err))
    end
  end

  run({ 'gh', 'pr', 'view', '--json', 'baseRefName,baseRefOid,url', '--jq', '[.baseRefName, .baseRefOid, .url] | @tsv' }, function(output)
    local target, commit, url = output:match('^([^\t]+)\t(%x+)\t([^\t]+)$')
    local repo = url and url:match('^(https://[^/]+/[^/]+/[^/]+)/pull/%d+$')
    if not target or not repo then
      fail('could not read the current PR target')
      return
    end
    run({ 'git', 'fetch', '--no-tags', repo, commit }, function()
      run({ 'git', 'merge-base', 'HEAD', commit }, function(base)
        if not base:match('^%x+$') then
          fail('could not find the PR merge base')
          return
        end
        change_base(base, 'PR changes against ' .. target .. ' (including local edits)')
      end)
    end)
  end)
end

return M
