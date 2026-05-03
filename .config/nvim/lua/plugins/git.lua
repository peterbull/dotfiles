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

          local current_branch = vim.fn.system('git branch --show-current'):gsub('\n', '')

          local function get_default_branch()
            local default_branch = vim.fn.system('git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null'):gsub('refs/remotes/origin/', ''):gsub('\n', '')
            if default_branch == '' then
              vim.fn.system 'git show-ref --verify --quiet refs/heads/main'
              if vim.v.shell_error == 0 then
                default_branch = 'main'
              else
                vim.fn.system 'git show-ref --verify --quiet refs/heads/master'
                default_branch = vim.v.shell_error == 0 and 'master' or 'main'
              end
            end
            return default_branch
          end

          local default_branch = get_default_branch()
          if current_branch == default_branch then
            vim.cmd 'DiffviewOpen'
            return
          end

          local merge_base = vim.fn.system('git merge-base HEAD ' .. default_branch):gsub('\n', '')
          if merge_base == '' or vim.v.shell_error ~= 0 then
            vim.notify('Could not find merge base', vim.log.levels.ERROR)
            return
          end
          vim.cmd('DiffviewOpen ' .. merge_base)
        end,
        desc = 'Diff vs branch point (merge base)',
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
        '<leader>gA',
        function()
          local lib = require 'diffview.lib'
          local current_branch = vim.fn.system('git branch --show-current'):gsub('\n', '')

          local function get_default_branch()
            local default_branch = vim.fn.system('git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null'):gsub('refs/remotes/origin/', ''):gsub('\n', '')
            if default_branch == '' then
              vim.fn.system 'git show-ref --verify --quiet refs/heads/main 2>/dev/null'
              if vim.v.shell_error == 0 then
                default_branch = 'main'
              else
                vim.fn.system 'git show-ref --verify --quiet refs/heads/master 2>/dev/null'
                default_branch = vim.v.shell_error == 0 and 'master' or 'main'
              end
            end
            return default_branch
          end

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
    end,
  },
}
