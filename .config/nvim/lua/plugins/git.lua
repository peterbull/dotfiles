-- Resolve the repo's default branch ("main" or "master"). The authoritative
-- source is origin/HEAD: it handles repos where BOTH branches exist but the
-- real default is still master (e.g. ctm-ui: origin/HEAD -> master). Only when
-- origin/HEAD is unset do we fall back to local refs, preferring master when
-- both exist.
local function get_default_branch()
  local out = vim.fn.system { 'git', 'symbolic-ref', 'refs/remotes/origin/HEAD' }
  local db = out:match 'refs/remotes/origin/([^%s]+)'
  if db then
    return db
  end

  local function ref_exists(ref)
    vim.fn.system { 'git', 'show-ref', '--verify', '--quiet', ref }
    return vim.v.shell_error == 0
  end
  local has_main = ref_exists 'refs/heads/main'
  local has_master = ref_exists 'refs/heads/master'
  if has_main and has_master then
    return 'master'
  elseif has_main then
    return 'main'
  end
  return 'master'
end

-- Undo the intent-to-add entries the branch-diff keymaps (<leader>gm / <leader>gM) create. Only
-- reset entries that still point at the empty blob, so a file the user
-- actually staged inside the diff view keeps its staged content.
local function cleanup_iadd()
  local pending = vim.g.diffview_iadd
  if not pending or #pending.files == 0 then
    return
  end
  vim.g.diffview_iadd = nil

  local out = vim.fn.system(vim.list_extend({ 'git', '-C', pending.toplevel, '-c', 'core.quotePath=false', 'ls-files', '--stage', '--' }, pending.files))
  local still = {}
  for _, line in ipairs(vim.split(out, '\n', { plain = true })) do
    local hash, path = line:match '^%d+%s+(%x+)%s+%d\t(.*)$'
    if hash == 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391' then
      still[#still + 1] = path
    end
  end
  if #still > 0 then
    vim.fn.system(vim.list_extend({ 'git', '-C', pending.toplevel, 'reset', '-q', '--' }, still))
  end
end

-- diffview only lists untracked files for index-vs-worktree diffs, so mark
-- untracked (non-ignored) files intent-to-add and open a working-tree diff
-- against `base_rev`; untracked files then show up as new files. cleanup_iadd()
-- undoes the index changes when the view closes (or on quit).
local function open_branch_diff(base_rev)
  local toplevel = vim.fn.system({ 'git', 'rev-parse', '--show-toplevel' }):gsub('%s', '')
  if toplevel == '' or vim.v.shell_error ~= 0 then
    vim.notify('Not in a git repo', vim.log.levels.ERROR)
    return
  end
  local untracked = vim.fn.system {
    'git',
    '-C',
    toplevel,
    '-c',
    'core.quotePath=false',
    'ls-files',
    '--others',
    '--exclude-standard',
  }
  local files = {}
  for _, f in ipairs(vim.split(untracked, '\n', { plain = true })) do
    if f ~= '' then
      files[#files + 1] = f
    end
  end
  if #files > 0 then
    vim.fn.system(vim.list_extend({ 'git', '-C', toplevel, 'add', '-N', '--' }, files))
  end
  vim.g.diffview_iadd = { toplevel = toplevel, files = files }
  vim.cmd('DiffviewOpen --untracked-files=all ' .. base_rev)
end

return {
  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory' },
    keys = {
      {
        '<leader>gM',
        function()
          local lib = require 'diffview.lib'
          if next(lib.views) ~= nil then
            vim.cmd 'DiffviewClose'
            return
          end
          vim.cmd 'DiffviewOpen --untracked-files=all'
        end,
        desc = 'Diff my worktree vs last commit (HEAD), incl. untracked',
      },
      {
        '<leader>gm',
        function()
          local lib = require 'diffview.lib'
          if next(lib.views) ~= nil then
            vim.cmd 'DiffviewClose'
            return
          end

          local current_branch = vim.fn.system({ 'git', 'branch', '--show-current' }):gsub('%s', '')
          local default_branch = get_default_branch()

          -- On the default branch there's no branch point to diff against;
          -- the plain view (worktree vs HEAD) includes untracked natively.
          if current_branch == default_branch then
            vim.cmd 'DiffviewOpen --untracked-files=all'
            return
          end

          local merge_base = vim.fn.system({ 'git', 'merge-base', 'HEAD', default_branch }):gsub('%s', '')
          if merge_base == '' or vim.v.shell_error ~= 0 then
            -- No local default branch (fresh/shallow clone): try the
            -- remote-tracking ref before giving up.
            merge_base = vim.fn.system({ 'git', 'merge-base', 'HEAD', 'origin/' .. default_branch }):gsub('%s', '')
          end
          if merge_base == '' or vim.v.shell_error ~= 0 then
            vim.notify("Could not find merge base with '" .. default_branch .. "'", vim.log.levels.ERROR)
            return
          end
          open_branch_diff(merge_base)
        end,
        desc = 'Diff vs branch point (merge base), incl. untracked',
      },
      {
        '<leader>gd',
        function()
          local lib = require 'diffview.lib'
          if next(lib.views) == nil then
            vim.cmd 'DiffviewOpen'
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = 'Current file changes (staged/unstaged)',
      },
      {
        '<leader>gf',
        function()
          local lib = require 'diffview.lib'
          if next(lib.views) == nil then
            vim.g.diffview_pinned_file = vim.fn.expand '%:p'
            vim.cmd 'DiffviewFileHistory %'
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = '[G]it [f]ile History',
      },
      {
        '<leader>gh',
        function()
          local lib = require 'diffview.lib'
          if next(lib.views) == nil then
            vim.cmd 'DiffviewFileHistory'
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = '[G]it [H]istory',
      },

      {
        '<leader>gT',
        function()
          local lib = require 'diffview.lib'
          if next(lib.views) ~= nil then
            vim.cmd 'DiffviewClose'
            return
          end

          vim.ui.input({ prompt = 'Base tag: ' }, function(tag1)
            if not tag1 or tag1 == '' then
              return
            end
            vim.ui.input({ prompt = 'Compare tag: ' }, function(tag2)
              if not tag2 or tag2 == '' then
                return
              end
              vim.cmd('DiffviewOpen ' .. tag1 .. '..' .. tag2)
            end)
          end)
        end,
        desc = '[G]it diff between two [T]ags',
      },
      {
        '<leader>gA',
        function()
          local lib = require 'diffview.lib'
          local current_branch = vim.fn.system({ 'git', 'branch', '--show-current' }):gsub('%s', '')
          local default_branch = get_default_branch()
          local cmd = current_branch == default_branch and 'DiffviewOpen' or ('DiffviewOpen ' .. default_branch)

          if next(lib.views) == nil then
            vim.cmd(cmd)
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = '[G]it [A]ll changes vs default branch',
      },
    },
    config = function()
      require('diffview').setup {
        use_icons = vim.g.have_nerd_font,
        view = {
          default = {
            layout = 'diff2_horizontal',
          },
        },
        keymaps = {
          file_history_panel = {
            {
              'n',
              'gd',
              function()
                local lib = require 'diffview.lib'
                local view = lib.get_current_view()
                if not view then
                  return
                end

                -- try different ways to get the entry under cursor
                local entry = view.panel:get_item_at_cursor()
                if not entry then
                  vim.notify('no entry under cursor', vim.log.levels.ERROR)
                  return
                end
                local hash = entry.commit and entry.commit.hash or entry.hash

                local file = vim.g.diffview_pinned_file
                if not file or file == '' then
                  vim.notify('No pinned file — open history with <leader>gf first', vim.log.levels.WARN)
                  return
                end

                vim.notify('hash: ' .. hash .. '\nfile: ' .. file, vim.log.levels.INFO, { timeout = 5000 })

                vim.cmd 'DiffviewClose'
                vim.schedule(function()
                  vim.cmd('DiffviewOpen ' .. hash .. '.. --imply-local -- ' .. vim.fn.fnameescape(file))
                end)
              end,
              { desc = 'Diff working tree vs commit under cursor' },
            },
          },
        },
      }

      -- Undo intent-to-add entries (see <leader>gM) when the diff view closes
      -- or on quit, so the index is left exactly as we found it.
      vim.api.nvim_create_autocmd('User', {
        pattern = 'DiffviewViewClosed',
        callback = cleanup_iadd,
      })
      vim.api.nvim_create_autocmd('VimLeavePre', {
        callback = cleanup_iadd,
      })
    end,
  },
  {
    'NeogitOrg/neogit',
    dependencies = {
      'sindrets/diffview.nvim',
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    cmd = 'Neogit',
    keys = {
      {
        '<leader>gg',
        function()
          require('neogit').open()
        end,
        desc = '[g]it [g]it (Neogit status)',
      },
      {
        '<leader>gc',
        function()
          require('neogit').open { 'commit' }
        end,
        desc = '[g]it [c]ommit',
      },
      {
        '<leader>gp',
        function()
          require('neogit').open { 'push' }
        end,
        desc = '[g]it [p]ush',
      },
      {
        '<leader>gP',
        function()
          require('neogit').open { 'pull' }
        end,
        desc = '[g]it [p]ull',
      },
      {
        '<leader>gl',
        function()
          require('neogit').open { 'log' }
        end,
        desc = '[g]it [l]og',
      },
      {
        '<leader>gB',
        function()
          require('neogit').open { 'branch' }
        end,
        desc = '[g]it [B]ranch',
      },
      {
        '<leader>gs',
        function()
          require('neogit').open { 'stash' }
        end,
        desc = '[g]it [s]tash',
      },
    },
    opts = {
      integrations = {
        diffview = true,
        telescope = true,
      },
    },
  },
}
