return {
  {
    'tpope/vim-fugitive',
    cmd = { 'Git', 'G', 'Gdiffsplit', 'Gread', 'Gwrite', 'Ggrep', 'GMove', 'GDelete', 'GBrowse' },
    keys = {
      -- Git status (like lazygit's main view)
      { '<leader>gs', '<cmd>Git<CR>', desc = 'Git Status' },

      -- Git log
      { '<leader>gl', '<cmd>Git log --oneline<CR>', desc = 'Git Log' },

      -- Git add current file
      { '<leader>ga', '<cmd>Gwrite<CR>', desc = 'Git Add Current File' },

      -- Git commit
      { '<leader>gc', '<cmd>Git commit<CR>', desc = 'Git Commit' },

      -- Git push
      { '<leader>gp', '<cmd>Git push<CR>', desc = 'Git Push' },

      -- Git pull
      { '<leader>gP', '<cmd>Git pull<CR>', desc = 'Git Pull' },
    },
  },
  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory' },
    keys = {
      {
        '<leader>gd',
        function()
          require 'diffview'
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
        '<leader>gm',
        function()
          require 'diffview'
          local lib = require 'diffview.lib'

          if next(lib.views) == nil then
            vim.cmd 'DiffviewOpen'
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = 'Diff vs previous commit',
      },

      {
        '<leader>gM',
        function()
          require 'diffview'
          local lib = require 'diffview.lib'

          -- Get current branch name
          local current_branch = vim.fn.system('git branch --show-current'):gsub('\n', '')

          -- Function to get the default branch (main or master)
          local function get_default_branch()
            -- Try to get the default branch from remote
            local default_branch = vim.fn.system('git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null'):gsub('refs/remotes/origin/', ''):gsub('\n', '')

            -- If that fails, check if main or master exists
            if default_branch == '' then
              local main_exists = vim.fn.system 'git show-ref --verify --quiet refs/heads/main 2>/dev/null'
              if vim.v.shell_error == 0 then
                default_branch = 'main'
              else
                local master_exists = vim.fn.system 'git show-ref --verify --quiet refs/heads/master 2>/dev/null'
                if vim.v.shell_error == 0 then
                  default_branch = 'master'
                else
                  default_branch = 'main' -- fallback
                end
              end
            end

            return default_branch
          end

          local default_branch = get_default_branch()
          local cmd

          if current_branch == default_branch then
            -- On default branch: show only working tree changes
            cmd = 'DiffviewOpen'
          else
            -- On feature branch: show all changes since default branch INCLUDING working tree
            cmd = 'DiffviewOpen ' .. default_branch
          end

          if next(lib.views) == nil then
            vim.cmd(cmd)
          else
            vim.cmd 'DiffviewClose'
          end
        end,
      },

      config = function()
        require('diffview').setup {
          use_icons = vim.g.have_nerd_font,
          view = {
            default = {
              layout = 'diff2_horizontal',
            },
          },
          keymap = {
            view = {
              -- Reset hunk in diffview
              ['<leader>grh'] = function()
                vim.cmd 'DiffviewClose'
                -- Switch to the actual file and reset hunk
                vim.schedule(function()
                  require('gitsigns').reset_hunk()
                end)
              end,
            },
          },
        }
      end,
    },
  },
}
