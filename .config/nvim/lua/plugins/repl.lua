return {
  {
    'benlubas/molten-nvim',
    version = '^1.0.0', -- use version <2.0.0 to avoid breaking changes
    dependencies = { '3rd/image.nvim' },
    build = ':UpdateRemotePlugins',
    init = function()
      -- these are examples, not defaults. Please see the readme
      vim.g.molten_image_provider = 'image.nvim'
      vim.g.molten_output_win_max_height = 20
    end,
    config = function()
      -- Keybindings for Molten
      vim.keymap.set('n', '<leader>mi', ':MoltenInit python3<CR>', { desc = 'Initialize Molten' })
      vim.keymap.set('n', '<leader>ml', ':MoltenEvaluateLine<CR>', { desc = 'Evaluate line' })
      vim.keymap.set('v', '<leader>me', ':<C-u>MoltenEvaluateVisual<CR>gv', { desc = 'Evaluate visual selection' })
      vim.keymap.set('n', '<leader>mc', ':MoltenReevaluateCell<CR>', { desc = 'Re-evaluate cell' })
      vim.keymap.set('n', '<leader>mo', ':MoltenShowOutput<CR>', { desc = 'Show output' })
      vim.keymap.set('n', '<leader>mh', ':MoltenHideOutput<CR>', { desc = 'Hide output' })
      vim.keymap.set('n', '<leader>md', ':MoltenDelete<CR>', { desc = 'Delete cell output' })
      vim.keymap.set('n', '<leader>mn', ':MoltenNext<CR>', { desc = 'Next cell' })
      vim.keymap.set('n', '<leader>mp', ':MoltenPrev<CR>', { desc = 'Previous cell' })
      vim.keymap.set('n', '<leader>mq', ':MoltenDeinit<CR>', { desc = 'Quit Molten' })
      vim.keymap.set('n', '<leader>mR', ':MoltenRestart<CR>', { desc = 'Restart Molten' })
      vim.keymap.set('n', '<leader>ma', ':MoltenEvaluateOperator<CR>gg0VG', { desc = 'Run all cells' })
      vim.keymap.set('n', '<leader>mx', ':MoltenHideOutput<CR>:MoltenDelete<CR>', { desc = 'Clear all outputs' })
    end,
  },
  {
    'Vigemus/iron.nvim',
    config = function()
      local iron = require 'iron.core'
      local view = require 'iron.view'
      local common = require 'iron.fts.common'
      --
      -- Test debug function
      local function debug_test()
        print 'DEBUG: Test function called!'
        local test_var = 'Hello from debug test'
        print('DEBUG: test_var =', test_var)
        -- This is where you'll set your breakpoint
        local another_var = 42
        print('DEBUG: another_var =', another_var)
        return test_var, another_var
      end

      iron.setup {
        config = {
          -- Whether a repl should be discarded or not
          scratch_repl = true,
          -- Your repl definitions come here
          repl_definition = {
            sh = {
              command = { 'zsh' },
            },
            python = {
              command = { 'python3' }, -- or { "ipython", "--no-autoindent" }
              format = common.bracketed_paste_python,
              block_dividers = { '# %%', '#%%' },
              env = { PYTHON_BASIC_REPL = '1' }, --this is needed for python3.13 and up.
            },

            javascript = {
              command = {
                'deno',
                'repl',
                '--allow-all',
                '--unstable-node-globals',
                '--unstable-byonm',
                '--unstable-ffi',
                '--unstable-bare-node-builtins',
              },
            },
            typescript = {
              command = {
                'deno',
                'repl',
                '--allow-all',
                '--unstable-node-globals',
                '--unstable-byonm',
                '--unstable-ffi',
                '--unstable-bare-node-builtins',
              },
            },
            rust = {
              command = { 'evcxr' },
            },
          },
          -- How the repl window will be displayed
          repl_open_cmd = view.split.vertical.rightbelow(0.4), -- 40% width on the right

          -- Set the file type of the newly created repl
          repl_filetype = function(bufnr, ft)
            return ft
          end,

          -- Send selections to the DAP repl if an nvim-dap session is running
          dap_integration = true,
        },

        keymaps = {
          toggle_repl = '<space>rr', -- Toggle REPL
          restart_repl = '<space>rR', -- Restart REPL
          send_motion = '<space>rc', -- Send motion (was <space>sc)
          visual_send = '<space>rc', -- Send visual selection (was <space>sc)
          send_file = '<space>rF', -- Send entire file (was <space>sf)
          send_line = '<space>rl', -- Send current line (was <space>sl)
          send_paragraph = '<space>rp', -- Send paragraph (was <space>sp)
          send_until_cursor = '<space>ru', -- Send until cursor (was <space>su)
          send_mark = '<space>rm', -- Send mark (was <space>sm)
          send_code_block = '<space>rb', -- Send code block (was <space>sb)
          send_code_block_and_move = '<space>rn', -- Send code block and move (was <space>sn)
          mark_motion = '<space>rmc', -- Mark motion (was <space>mc)
          mark_visual = '<space>rmc', -- Mark visual (was <space>mc)
          remove_mark = '<space>rmd', -- Remove mark (was <space>md)
          cr = '<space>r<cr>', -- Send carriage return (was <space>s<cr>)
          interrupt = '<space>ri', -- Interrupt (was <space>s<space>)
          exit = '<space>rq', -- Exit REPL (was <space>sq)
          clear = '<space>rcl', -- Clear REPL (was <space>cl)
        },

        -- Highlight settings
        highlight = {
          italic = true,
        },
        ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
      }

      -- Additional keymaps
      vim.keymap.set('n', '<space>rf', '<cmd>IronFocus<cr>', { desc = 'Focus REPL' })
      vim.keymap.set('n', '<space>rh', '<cmd>IronHide<cr>', { desc = 'Hide REPL' })
      vim.keymap.set('n', '<space>rt', function()
        print 'DEBUG: Test keymap pressed!'
        debug_test()
      end, { desc = 'Debug Test Function' })
    end,
  },
}
