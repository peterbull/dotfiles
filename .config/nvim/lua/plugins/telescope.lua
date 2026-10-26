return {
  'nvim-telescope/telescope.nvim',
  version = '0.2.*',
  event = 'VimEnter',
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'nvim-telescope/telescope-fzf-native.nvim',

      build = 'make',

      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    { 'nvim-telescope/telescope-ui-select.nvim' },

    { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
  },
  config = function()
    require('telescope').setup {
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown {
            layout_config = { width = 0.8 },
          },
        },
      },
    }

    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')

    local builtin = require 'telescope.builtin'
    vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
    vim.keymap.set('n', '<leader>sF', builtin.find_files, { desc = '[s]earch [F]iles - incl. extras' })

    vim.keymap.set('n', '<leader>sf', function()
      builtin.find_files {
        glob_pattern = '!*.test.*',
      }
    end, { desc = '[s]earch [f]iles' })
    vim.keymap.set('n', '<leader>sss', builtin.builtin, { desc = '[S]earch [S]elect [S]elect Telescope' })
    vim.keymap.set('n', '<leader>ssw', builtin.lsp_dynamic_workspace_symbols, { desc = '[S]earch [S]ymbols [W]orkspace' })
    vim.keymap.set('n', '<leader>ssd', builtin.lsp_document_symbols, { desc = '[S]earch [S]ymbols [D]ocument' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
    vim.keymap.set('n', '<leader>sg', function()
      builtin.live_grep { glob_pattern = '!*test.*' }
    end, { desc = '[s]earch by [g]rep' })
    vim.keymap.set('n', '<leader>sG', builtin.live_grep, { desc = '[s]earch by [G]rep - incl. tests' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
    vim.keymap.set('n', '<leader>sj', builtin.jumplist, { desc = '[S]earch [J]umplist' })
    vim.keymap.set('n', '<leader>sm', builtin.marks, { desc = '[S]earch [M]arks' })

    vim.keymap.set('n', '<leader>saf', function()
      builtin.find_files { hidden = true, no_ignore = true }
    end, { desc = '[S]earch [A]ll [F]iles, includes hidden' })

    vim.keymap.set('n', '<leader>sag', function()
      builtin.live_grep {
        additional_args = function()
          return {
            '--hidden',
            '--no-ignore',
            '--glob',
            '!**/node_modules/**',
            '--glob',
            '!**/.venv/**',
            '--glob',
            '!**/.git/**',
            '--glob',
            '!**/dist/**',
            '--glob',
            '!**/build/**',
            '--glob',
            '!**/__pycache__/**',
            '--glob',
            '!**/.next/**',
            '--glob',
            '!**/coverage/**',
          }
        end,
      }
    end, { desc = '[S]earch in [A]ll Files by [G]rep' })

    vim.keymap.set('n', '<leader>/', function()
      builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        winblend = 10,
        previewer = false,
      })
    end, { desc = '[/] Fuzzily search in current buffer' })

    vim.keymap.set('n', '<leader>s/', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Live Grep in Open Files',
      }
    end, { desc = '[S]earch [/] in Open Files' })

    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = '[S]earch [N]eovim files' })
  end,
}
