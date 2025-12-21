-- Set <space> as the leader key
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

--- https://github.com/fredrikaverpil/dotfiles/blob/82b161d397d27772e2eb34422058df5fd44b06a7/nvim-fredrik/lua/fredrik/init.lua#L7
---@diagnostic disable-next-line: undefined-global
if init_debug then
  local osvpath = vim.fn.stdpath 'data' .. '/lazy/one-small-step-for-vimkind'
  vim.opt.rtp:prepend(osvpath)
  require('osv').launch { port = 8086, blocking = true }
end

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = false

require 'config.options'
require 'config.keymaps'
require 'config.autocmds'

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end

---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

require('lazy').setup({
  { import = 'plugins' },

  { -- Autocompletion
    'saghen/blink.cmp',
    event = 'VimEnter',
    version = '1.*',
    dependencies = {
      -- Snippet Engine
      {
        'L3MON4D3/LuaSnip',
        version = '2.*',
        build = (function()
          -- Build Step is needed for regex support in snippets.
          -- This step is not supported in many windows environments.
          -- Remove the below condition to re-enable on windows.
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = {
          -- `friendly-snippets` contains a variety of premade snippets.
          --    See the README about individual language/framework/plugin snippets:
          --    https://github.com/rafamadriz/friendly-snippets
          {
            'rafamadriz/friendly-snippets',
            config = function()
              require('luasnip.loaders.from_vscode').lazy_load()
            end,
          },
        },
        opts = {

          menu = {

            draw = {
              columns = {
                { 'kind_icon', 'label', gap = 1 },
                { 'kind' },
              },
              components = {
                kind_icon = {
                  text = function(item)
                    local kind = require('lspkind').symbol_map[item.kind] or ''
                    return kind .. ' '
                  end,
                  highlight = 'CmpItemKind',
                },
                label = {
                  text = function(item)
                    return item.label
                  end,
                  highlight = 'CmpItemAbbr',
                },
                kind = {
                  text = function(item)
                    return item.kind
                  end,
                  highlight = 'CmpItemKind',
                },
              },
            },
          },
        },
      },
      'folke/lazydev.nvim',
    },
    --- @module 'blink.cmp'
    --- @type blink.cmp.Config
    opts = {
      keymap = {
        -- 'default' (recommended) for mappings similar to built-in completions
        --   <c-y> to accept ([y]es) the completion.
        --    This will auto-import if your LSP supports it.
        --    This will expand snippets if the LSP sent a snippet.
        -- 'super-tab' for tab to accept
        -- 'enter' for enter to accept
        -- 'none' for no mappings
        --
        -- For an understanding of why the 'default' preset is recommended,
        -- you will need to read `:help ins-completion`
        --
        -- No, but seriously. Please read `:help ins-completion`, it is really good!
        --
        -- All presets have the following mappings:
        -- <tab>/<s-tab>: move to right/left of your snippet expansion
        -- <c-space>: Open menu or open docs if already open
        -- <c-n>/<c-p> or <up>/<down>: Select next/previous item
        -- <c-e>: Hide menu
        -- <c-k>: Toggle signature help
        --
        -- See :h blink-cmp-config-keymap for defining your own keymap
        preset = 'default',

        -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
        --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
      },

      appearance = {
        -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
        -- Adjusts spacing to ensure icons are aligned
        nerd_font_variant = 'mono',
      },

      completion = {
        -- By default, you may press `<c-space>` to show the documentation.
        -- Optionally, set `auto_show = true` to show the documentation after a delay.
        documentation = { auto_show = false, auto_show_delay_ms = 500 },
      },

      sources = {
        default = { 'lsp', 'path', 'snippets', 'lazydev' },
        providers = {
          lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
        },
      },

      snippets = { preset = 'luasnip' },

      -- Blink.cmp includes an optional, recommended rust fuzzy matcher,
      -- which automatically downloads a prebuilt binary when enabled.
      --
      -- By default, we use the Lua implementation instead, but you may enable
      -- the rust implementation via `'prefer_rust_with_warning'`
      --
      -- See :h blink-cmp-config-fuzzy for more information
      fuzzy = { implementation = 'lua' },

      -- Shows a signature help window while you type arguments for a function
      signature = { enabled = true },
    },
  },

  -- { -- You can easily change to a different colorscheme.
  --   -- Change the name of the colorscheme plugin below, and then
  --   -- change the command in the config to whatever the name of that colorscheme is.
  --   --
  --   -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
  --   'folke/tokyonight.nvim',
  --   priority = 1000, -- Make sure to load this before all the other start plugins.
  --   config = function()
  --     ---@diagnostic disable-next-line: missing-fields
  --     require('tokyonight').setup {
  --       styles = {
  --         comments = { italic = true },
  --         keywords = { italic = true },
  --         functions = { bold = true },
  --       },
  --     }
  --
  --     -- Load the colorscheme here.
  --     -- Like many other themes, this one has different styles, and you could load
  --     -- any other, such as 'tokyonight-storm', 'tokyonight-moon', or 'tokyonight-day'.
  --     vim.cmd.colorscheme 'tokyonight-storm'
  --   end,
  -- },
  {
    'olimorris/onedarkpro.nvim',
    priority = 1000,
    config = function()
      require('onedarkpro').setup {
        highlights = {
          ['@lsp.typemod.variable.readonly.typescript'] = { fg = '#f0d090' },
          -- ['@type'] = { fg = '#f5e6b8' },
          ['@type.builtin'] = { fg = '#e0a070' },
          -- ['@type'] = { fg = '#fde68a', style = 'italic' }, -- Light gold
          ['@type'] = { fg = '#d8b4fe', style = 'italic' }, -- Light purple
          -- ['@type'] = { fg = '#7dd3fc' },
          -- ['@lsp.type.class'] = { fg = '#d8b4fe', style = 'italic' }, -- Light purple
          ['@lsp.typemod.variable.readonly.typescriptreact'] = { fg = '#e0de84' }, -- 25% lighter

          -- light blue arrow func
          ['@lsp.typemod.function.declaration.typescript'] = { fg = '#7dd3fc' },
          ['@lsp.typemod.function.readonly.typescript'] = { fg = '#7dd3fc' },

          -- python type hints
          ['@lsp.type.namespace.python'] = { fg = '#f0d090', style = 'italic' },
          ['@lsp.type.class.python'] = { fg = '#f0d090', style = 'italic' },
          Type = { fg = '#d19a66' },
        },

        styles = {
          functions = 'bold',
          comments = 'italic',
          variables = 'NONE',
          types = 'NONE',
        },
      }
      vim.cmd 'colorscheme onedark'
    end,
  },
  -- Highlight todo, notes, etc in comments
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },

  { -- Collection of various small independent plugins/modules
    'echasnovski/mini.nvim',
    config = function()
      -- Better Around/Inside textobjects
      --
      -- Examples:
      --  - va)  - [V]isually select [A]round [)]paren
      --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
      --  - ci'  - [C]hange [I]nside [']quote
      require('mini.ai').setup { n_lines = 500 }

      -- Add/delete/replace surroundings (brackets, quotes, etc.)
      --
      -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
      -- - sd'   - [S]urround [D]elete [']quotes
      -- - sr)'  - [S]urround [R]eplace [)] [']
      require('mini.surround').setup()

      -- Simple and easy statusline.
      --  You could remove this setup call if you don't like it,
      --  and try some other statusline plugin
      local statusline = require 'mini.statusline'
      -- set use_icons to true if you have a Nerd Font
      statusline.setup { use_icons = vim.g.have_nerd_font }

      -- You can configure sections in the statusline by overriding their
      -- default behavior. For example, here we set the section for
      -- cursor location to LINE:COLUMN
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function()
        return '%2l:%-2v'
      end

      -- ... and there is more!
      --  Check out: https://github.com/echasnovski/mini.nvim
      require('mini.files').setup()

      local yank_file_content = function()
        local MiniFiles = require 'mini.files'
        local entry = MiniFiles.get_fs_entry()
        if not entry then
          return vim.notify 'Cursor is not on valid entry'
        end

        local path = entry.path

        if entry.fs_type == 'file' then
          local lines = vim.fn.readfile(path)
          local content = '## ' .. path .. '\n\n' .. table.concat(lines, '\n')

          -- Append to clipboard
          local current_clipboard = vim.fn.getreg '+'
          local new_content = current_clipboard .. '\n' .. content .. '\n'
          vim.fn.setreg('+', new_content)

          vim.notify('Appended file content to clipboard: ' .. path)
        else
          -- for directories do nothing,
        end
      end

      vim.api.nvim_create_autocmd('User', {
        pattern = 'MiniFilesBufferCreate',
        callback = function(args)
          local buf_id = args.data.buf_id
          vim.keymap.set('n', 'gy', yank_file_content, { buffer = buf_id, desc = 'Yank path' })
        end,
      })
      vim.keymap.set('n', '<leader>e', function()
        local mini_files = require 'mini.files'
        mini_files.open(vim.api.nvim_buf_get_name(0), false)
        mini_files.reveal_cwd()
      end, { desc = 'Open mini file [E]xplorer' })
    end,
  },
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs', -- Sets main module to use for opts
    -- [[ Configure Treesitter ]] See `:help nvim-treesitter`
    opts = {
      ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
      -- Autoinstall languages that are not installed
      auto_install = true,
      highlight = {
        enable = true,
        -- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
        --  If you are experiencing weird indenting issues, add the language to
        --  the list of additional_vim_regex_highlighting and disabled languages for indent.
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = { enable = true, disable = { 'ruby' } },
    },
    -- There are additional nvim-treesitter modules that you can use to interact
    -- with nvim-treesitter. You should go explore a few and see what interests you:
    --
    --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
    --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
    --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
  },

  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs',
    opts = {
      ensure_installed = {
        'bash',
        'c',
        'cpp',
        'diff',
        'html',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'query',
        'vim',
        'vimdoc',
        'javascript',
        'typescript',
        'json',
      },
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = { enable = true, disable = { 'ruby' } },
    },
  },

  -- https://github.com/nicbytes/nvim/commit/a6022c8cc1166f4a87315b3c2199476101239b8b#diff-198b05cba517df75101c39ad19ff87fed6db322ea83a1af861c2ae7105b3ba4bR200
  -- for rust formatting in lldb

  {
    'mrcjkb/rustaceanvim',
    version = '^5',
    lazy = false,
    config = function()
      vim.g.rustaceanvim = {
        dap = {
          load_rust_types = true,
        },
      }
    end,
  },
  -- Debug setup
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'jbyuki/one-small-step-for-vimkind',
      'nvim-neotest/nvim-nio',
      { 'theHamsta/nvim-dap-virtual-text', opts = {} },
      {
        'mfussenegger/nvim-dap-python',
        config = function()
          require('dap-python').setup 'python3'

          local dap = require 'dap'

          table.insert(dap.configurations.python, {
            name = 'Docker: Airflow Worker',
            type = 'python',
            request = 'attach',
            connect = {
              port = 5679,
              host = 'localhost',
            },
            pathMappings = {
              {
                localRoot = vim.fn.getcwd(),
                remoteRoot = '/opt/airflow',
              },
            },
            justMyCode = false,
            showReturnValue = true,
          })

          -- For attaching
          vim.defer_fn(function()
            print('Adapter type after setup:', type(dap.adapters.python))
            if type(dap.adapters.python) ~= 'function' then
              dap.adapters.python = function(cb, config)
                if config.request == 'attach' then
                  local port = (config.connect or config).port
                  local host = (config.connect or config).host or '127.0.0.1'
                  print('Connecting to ' .. host .. ':' .. port)
                  cb {
                    type = 'server',
                    port = port,
                    host = host,
                    options = { source_filetype = 'python' },
                  }
                else
                  cb {
                    type = 'executable',
                    command = '/Users/peterbull/.local/share/nvim/mason/bin/debugpy-adapter',
                    options = { source_filetype = 'python' },
                  }
                end
              end
            end
          end, 100)
        end,
        ft = 'python',
      },
      {
        'jay-babu/mason-nvim-dap.nvim',
        dependencies = 'mason.nvim',
        cmd = { 'DapInstall', 'DapUninstall' },
        opts = {
          automatic_installation = true,
          handlers = {},
          ensure_installed = {
            'js-debug-adapter',
            'codelldb',
          },
        },
      },
      {
        'mason-org/mason.nvim',
        opts = function(_, opts)
          opts.ensure_installed = opts.ensure_installed or {}
          vim.list_extend(opts.ensure_installed, {
            'js-debug-adapter',
            'codelldb',
          })
        end,
      },
    },
    keys = {
      {
        '<F5>',
        function()
          require('dap').continue()
        end,
        desc = 'Debug: Start/Continue',
      },
      {
        '<F11>',
        function()
          require('dap').step_into()
        end,
        desc = 'Debug: Step Into',
      },
      {
        '<F10>',
        function()
          require('dap').step_over()
        end,
        desc = 'Debug: Step Over',
      },
      {
        '<F9>',
        function()
          require('dap').step_out()
        end,
        desc = 'Debug: Step Out',
      },
      {
        '<F7>',
        function()
          require('dapui').toggle()
        end,
        desc = 'Debug: Toggle UI',
      },
      {
        '<leader>dB',
        function()
          require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
        end,
        desc = 'Breakpoint Condition',
      },
      {
        '<leader>db',
        function()
          require('dap').toggle_breakpoint()
        end,
        desc = 'Toggle Breakpoint',
      },
      {
        '<leader>dc',
        function()
          require('dap').continue()
        end,
        desc = 'Run/Continue',
      },
      {
        '<leader>dC',
        function()
          require('dap').run_to_cursor()
        end,
        desc = 'Run to Cursor',
      },
      {
        '<leader>dg',
        function()
          require('dap').goto_()
        end,
        desc = 'Go to Line (No Execute)',
      },
      {
        '<leader>di',
        function()
          require('dap').step_into()
        end,
        desc = 'Step Into',
      },
      {
        '<leader>dj',
        function()
          require('dap').down()
        end,
        desc = 'Down',
      },
      {
        '<leader>dk',
        function()
          require('dap').up()
        end,
        desc = 'Up',
      },
      {
        '<leader>dl',
        function()
          require('dap').run_last()
        end,
        desc = 'Run Last',
      },
      {
        '<leader>do',
        function()
          require('dap').step_out()
        end,
        desc = 'Step Out',
      },
      {
        '<leader>dO',
        function()
          require('dap').step_over()
        end,
        desc = 'Step Over',
      },
      {
        '<leader>dP',
        function()
          require('dap').pause()
        end,
        desc = 'Pause',
      },
      {
        '<leader>dr',
        function()
          require('dap').repl.toggle()
        end,
        desc = 'Toggle REPL',
      },
      {
        '<leader>ds',
        function()
          require('dap').session()
        end,
        desc = 'Session',
      },
      {
        '<leader>dt',
        function()
          require('dap').terminate()
        end,
        desc = 'Terminate',
      },
      {
        '<leader>dw',
        function()
          require('dap.ui.widgets').hover()
        end,
        desc = 'Widgets',
      },
      {
        '<leader>dL',
        function()
          require('dap.ext.vscode').load_launchjs()
        end,
        desc = 'Load launch.json',
      },
      {
        '<leader>da',
        function()
          vim.cmd 'DapNew Debug\\ pnpm\\ dev\\ (Node.js) Next.js:\\ debug\\ client-side Attach\\ to\\ Pipeline'
        end,
        desc = 'Launch compound',
      },
      {
        '<leader>dE',
        function()
          local dap = require 'dap'
          local breakpoints = require 'dap.breakpoints'

          if vim.g.dap_breakpoints_saved then
            -- Restore breakpoints
            for bufnr, buf_bps in pairs(vim.g.dap_breakpoints_saved) do
              for _, bp in pairs(buf_bps) do
                breakpoints.set({
                  condition = bp.condition,
                  hit_condition = bp.hitCondition,
                  log_message = bp.logMessage,
                }, bufnr, bp.line)
              end
            end
            vim.g.dap_breakpoints_saved = nil
            vim.notify('Breakpoints restored', vim.log.levels.INFO)
          else
            -- Save and clear breakpoints
            local bps = breakpoints.get()
            local has_breakpoints = false
            for _, buf_bps in pairs(bps) do
              if next(buf_bps) then
                has_breakpoints = true
                break
              end
            end

            if has_breakpoints then
              vim.g.dap_breakpoints_saved = vim.deepcopy(bps)
              dap.clear_breakpoints()
              vim.notify('Breakpoints cleared (saved)', vim.log.levels.INFO)
            else
              vim.notify('No breakpoints to clear', vim.log.levels.INFO)
            end
          end
        end,
        desc = 'Toggle Clear/Restore All Breakpoints',
      },
      {
        '<leader>dR',
        function()
          local dap = require 'dap'
          dap.clear_breakpoints()
          vim.g.dap_breakpoints_saved = nil
          vim.notify('All breakpoints permanently removed', vim.log.levels.INFO)
        end,
        desc = 'Remove All Breakpoints Permanently',
      },
    },
    config = function()
      local dap = require 'dap'

      -- Enable DAP logging for debugging issues
      dap.set_log_level 'INFO'

      -- Setup pwa-node adapter (JavaScript/TypeScript)
      dap.adapters['pwa-node'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = {
            vim.fn.stdpath 'data' .. '/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js',
            '${port}',
          },
        },
      }

      -- Setup node adapter (compatibility layer)
      dap.adapters['node'] = function(cb, config)
        if config.type == 'node' then
          config.type = 'pwa-node'
        end
        local nativeAdapter = dap.adapters['pwa-node']
        if type(nativeAdapter) == 'function' then
          nativeAdapter(cb, config)
        else
          cb(nativeAdapter)
        end
      end

      -- Setup Chrome adapter
      dap.adapters['pwa-chrome'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = {
            vim.fn.stdpath 'data' .. '/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js',
            '${port}',
          },
        },
      }

      -- Setup LLDB adapter for C/C++/Rust
      dap.adapters.lldb = {
        type = 'executable',
        command = vim.fn.stdpath 'data' .. '/mason/packages/codelldb/extension/adapter/codelldb',
        name = 'lldb',
      }

      -- Setup codelldb adapter (alternative name)
      dap.adapters.codelldb = dap.adapters.lldb

      -- Bash Debug Adapter Setup
      dap.adapters.sh = {
        type = 'executable',
        command = vim.fn.stdpath 'data' .. '/mason/bin/bash-debug-adapter',
        name = 'sh',
      }

      -- -- LUA
      -- dap.adapters['local-lua'] = {
      --   type = 'executable',
      --   command = 'node',
      --   args = {
      --     vim.fn.stdpath 'data' .. '/mason/packages/local-lua-debugger-vscode/extension/extension/debugAdapter.js',
      --   },
      --   enrich_config = function(config, on_config)
      --     if not config['extensionPath'] then
      --       local c = vim.deepcopy(config)
      --       c.extensionPath = vim.fn.stdpath 'data' .. '/mason/packages/local-lua-debugger-vscode/extension/'
      --       on_config(c)
      --     else
      --       on_config(config)
      --     end
      --   end,
      -- }
      -- dap.configurations.lua = {
      --   {
      --     name = 'Current file (local-lua-dbg, nlua)',
      --     type = 'local-lua',
      --     request = 'launch',
      --     cwd = '${workspaceFolder}',
      --     program = {
      --       lua = 'nlua.lua',
      --       file = '${file}',
      --     },
      --     verbose = true,
      --     args = {},
      --   },
      -- }

      dap.configurations.lua = {
        {
          type = 'nlua',
          request = 'attach',
          name = 'Attach to running Neovim instance',
        },
      }
      dap.adapters.nlua = function(callback, config)
        callback { type = 'server', host = config.host or '127.0.0.1', port = config.port or 8086 }
      end
      vim.keymap.set('n', '<leader>dN', function()
        require('osv').launch { port = 8086 }
      end, { noremap = true, desc = 'Launch [N]vim Debug Server' })
      vim.keymap.set('n', '<leader>dw', function()
        local widgets = require 'dap.ui.widgets'
        widgets.hover()
      end, { noremap = true, desc = 'Hover [W]idget' })

      local js_filetypes = { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' }

      -- Setup vscode compatibility
      local vscode = require 'dap.ext.vscode'
      vscode.type_to_filetypes['node'] = js_filetypes
      vscode.type_to_filetypes['pwa-node'] = js_filetypes
      vscode.type_to_filetypes['pwa-chrome'] = js_filetypes
      vscode.type_to_filetypes['lldb'] = { 'c', 'cpp', 'rust', 'zig' }
      vscode.type_to_filetypes['codelldb'] = { 'c', 'cpp', 'rust', 'zig' }
      vscode.type_to_filetypes['sh'] = { 'sh', 'bash' }
      -- Setup JavaScript/TypeScript configurations
      for _, language in ipairs(js_filetypes) do
        dap.configurations[language] = {
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Launch Current Node File(File Dir)',
            program = '${file}',
            cwd = '${fileDirName}',
            console = 'integratedTerminal',
          },
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Launch Current Node File (Project Dir with args)',
            program = '${file}',
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            args = function()
              local args_str = vim.fn.input 'Arguments: '
              return vim.split(args_str, ' ')
            end,
          },
          {
            type = 'pwa-node',
            request = 'attach',
            name = 'Attach',
            processId = require('dap.utils').pick_process,
            cwd = '${workspaceFolder}',
          },
        }
      end

      local function get_rust_package_name()
        local cargo_toml_path = vim.fn.getcwd() .. '/Cargo.toml'

        if vim.fn.filereadable(cargo_toml_path) == 1 then
          local cargo_content = vim.fn.readfile(cargo_toml_path)

          for _, line in ipairs(cargo_content) do
            local name = line:match '^name%s*=%s*"([^"]+)"'
            if name then
              return name
            end
          end
        end

        return nil
      end

      -- C/Rust config
      dap.configurations.c = {
        {
          name = 'Launch C Default',
          type = 'lldb',
          request = 'launch',
          program = function()
            local extension = vim.fn.expand '%:e'
            if extension == 'c' then
              local result = vim.fn.system 'make'
              if vim.v.shell_error ~= 0 then
                vim.notify('Build failed: ' .. result, vim.log.levels.ERROR)
                return nil
              end
              local exe_path = vim.fn.getcwd() .. '/build/main'

              vim.fn.system('chmod +x ' .. exe_path)
              return exe_path
            end
            if extension == 'rs' then
              local result = vim.fn.system 'cargo build'
              if vim.v.shell_error ~= 0 then
                vim.notify('Build failed: ' .. result, vim.log.levels.ERROR)
                return nil
              end
            end
            local package_name = get_rust_package_name() or 'backend'
            local exe_path = vim.fn.getcwd() .. '/target/debug/' .. package_name
            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
      }

      dap.configurations.rust = {
        {
          name = 'Launch Rust Workspace',
          type = 'lldb',
          request = 'launch',
          program = function()
            local result = vim.fn.system 'cargo build'
            if vim.v.shell_error ~= 0 then
              vim.notify('Cargo build failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            local package_name = get_rust_package_name() or 'backend'
            local exe_path = vim.fn.getcwd() .. '/target/debug/' .. package_name
            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
        {
          name = 'Launch Rust Current File',
          type = 'lldb',
          request = 'launch',
          program = function()
            local current_file = vim.fn.expand '%:p'
            local file_name = vim.fn.expand '%:t:r'
            local exe_path = vim.fn.getcwd() .. '/target/debug/' .. file_name

            vim.fn.system('mkdir -p ' .. vim.fn.getcwd() .. '/target/debug')

            local compile_cmd = string.format('rustc -g --edition 2021 -o %s %s', exe_path, current_file)
            local result = vim.fn.system(compile_cmd)

            if vim.v.shell_error ~= 0 then
              vim.notify('Rust compile failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
      }

      dap.configurations.zig = {
        {
          name = 'Launch Zig Workspace',
          type = 'lldb',
          request = 'launch',
          program = function()
            local result = vim.fn.system 'zig build'
            if vim.v.shell_error ~= 0 then
              vim.notify('Zig build failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            local exe_path = vim.fn.getcwd() .. '/zig-out/bin/'
            local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
            -- zig renames with underscore on build
            project_name = string.gsub(project_name, '-', '_')
            exe_path = exe_path .. project_name

            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
          initCommands = {
            'type format add --format decimal uint8_t',
            'type format add --format decimal "unsigned char"',
          },
        },
        {
          name = 'Launch Zig Current File',
          type = 'lldb',
          request = 'launch',
          program = function()
            local current_file = vim.fn.expand '%:p'
            local file_name = vim.fn.expand '%:t:r'
            local exe_path = vim.fn.getcwd() .. '/zig-out/bin/' .. file_name

            vim.fn.system('mkdir -p ' .. vim.fn.getcwd() .. '/zig-out/bin')

            local compile_cmd = string.format('zig build-exe -femit-bin=%s %s', exe_path, current_file)
            local result = vim.fn.system(compile_cmd)

            if vim.v.shell_error ~= 0 then
              vim.notify('Zig compile failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
          initCommands = {
            'type format add --format decimal uint8_t',
            'type format add --format decimal "unsigned char"',
          },
        },
      }
      dap.configurations.cpp = dap.configurations.c
      dap.configurations.sh = {
        {
          name = 'Launch Bash debugger',
          type = 'sh',
          request = 'launch',
          program = '${file}',
          cwd = '${fileDirname}',
          pathBashdb = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb',
          pathBashdbLib = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir',
          pathBash = 'bash',
          pathCat = 'cat',
          pathMkfifo = 'mkfifo',
          pathPkill = 'pkill',
          env = {},
          args = {},
          stopOnEntry = false,
        },
        {
          name = 'Launch Bash Script with Args',
          type = 'sh',
          request = 'launch',
          program = '${file}',
          cwd = '${fileDirname}',
          pathBashdb = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb',
          pathBashdbLib = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir',
          pathBash = 'bash',
          pathCat = 'cat',
          pathMkfifo = 'mkfifo',
          pathPkill = 'pkill',
          env = {},
          stopOnEntry = false,
          args = function()
            local args_str = vim.fn.input 'Arguments: '
            return vim.split(args_str, ' ')
          end,
        },
      }

      -- Also support .bash files
      dap.configurations.bash = dap.configurations.sh

      -- Also support .bash files
      dap.configurations.bash = dap.configurations.sh

      -- dap.configurations.lua = {
      --   {
      --     name = 'Current file (local-lua-dbg, lua)',
      --     type = 'nlua',
      --     request = 'launch',
      --     cwd = '${workspaceFolder}',
      --     program = {
      --       lua = 'nlua',
      --       file = '${file}',
      --     },
      --     args = {},
      --     verbose = true,
      --   },
      -- }

      -- Auto-load launch.json when entering a directory
      vim.api.nvim_create_autocmd('DirChanged', {
        callback = function()
          local launch_json = vim.fn.getcwd() .. '/.vscode/launch.json'
          if vim.fn.filereadable(launch_json) == 1 then
            require('dap.ext.vscode').load_launchjs(launch_json, {
              ['pwa-node'] = js_filetypes,
              ['pwa-chrome'] = js_filetypes,
              ['node'] = js_filetypes,
              ['chrome'] = js_filetypes,
              ['lldb'] = { 'c', 'cpp', 'rust' },
              ['codelldb'] = { 'c', 'cpp', 'rust' },
              ['sh'] = { 'sh', 'bash' },
            })
            print('Auto-loaded: ' .. launch_json)
          end
        end,
      })

      -- Also load launch.json on startup if it exists
      local startup_launch_json = vim.fn.getcwd() .. '/.vscode/launch.json'
      if vim.fn.filereadable(startup_launch_json) == 1 then
        require('dap.ext.vscode').load_launchjs(startup_launch_json, {
          ['pwa-node'] = js_filetypes,
          ['pwa-chrome'] = js_filetypes,
          ['node'] = js_filetypes,
          ['chrome'] = js_filetypes,
          ['lldb'] = { 'c', 'cpp', 'rust' },
          ['codelldb'] = { 'c', 'cpp', 'rust' },
          ['bashdb'] = { 'sh', 'bash' },
          ['sh'] = { 'sh', 'bash' },
        })
      end

      -- Set up highlights
      vim.api.nvim_set_hl(0, 'DapStoppedLine', { default = true, link = 'Visual' })

      -- Set up DAP signs
      local dap_icons = {
        Stopped = { '󰁕 ', 'DiagnosticWarn', 'DapStoppedLine' },
        Breakpoint = ' ',
        BreakpointCondition = ' ',
        BreakpointRejected = { ' ', 'DiagnosticError' },
        LogPoint = '.>',
      }

      for name, sign in pairs(dap_icons) do
        vim.fn.sign_define('Dap' .. name, {
          text = sign[1],
          texthl = sign[2] or 'DiagnosticInfo',
          linehl = sign[3],
          numhl = sign[3],
        })
      end

      vim.api.nvim_create_user_command('DapStatus', function()
        print('DAP adapters:', vim.inspect(vim.tbl_keys(dap.adapters)))
        if dap.get_log_file_path then
          print('DAP log file:', dap.get_log_file_path())
        end
        local js_configs = dap.configurations.javascript or {}
        print('JavaScript configs:', #js_configs)
        local c_configs = dap.configurations.c or {}
        print('C configs:', #c_configs)
      end, { desc = 'Show DAP status' })
    end,
  },
  {
    'jonathan-elize/dap-info.nvim',
    dependencies = {
      'mfussenegger/nvim-dap',
    },
    config = function()
      require('dap-info').setup {}
    end,
  },

  -- fancy UI for the debugger
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'nvim-neotest/nvim-nio' },
    keys = {
      {
        '<leader>du',
        function()
          require('dapui').toggle {}
        end,
        desc = 'Dap UI',
      },
      {
        '<leader>dU',
        function()
          local dapui = require 'dapui'
          dapui.close()
          dapui.open { reset = true }
        end,
        desc = 'Reset Dap UI',
      },
      {
        '<leader>de',
        function()
          require('dapui').eval()
        end,
        desc = 'Eval',
        mode = { 'n', 'v' },
      },
    },
    opts = {},
    config = function(_, opts)
      local dap = require 'dap'
      local dapui = require 'dapui'
      dapui.setup(opts)
      dap.listeners.after.event_initialized['dapui_config'] = function()
        -- dapui.open {}
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        -- dapui.close {}
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        -- dapui.close {}
      end
    end,
  },
  {
    -- Lua
    {
      'folke/persistence.nvim',
      event = 'BufReadPre', -- this will only start session saving when an actual file was opened
      opts = {
        -- add any custom options here
      },
      keys = {
        {
          '<leader>qs',
          function()
            require('persistence').load()
          end,
          desc = 'Load session for current dir',
        },
        {
          '<leader>qS',
          function()
            require('persistence').select()
          end,
          desc = 'Select session to load',
        },
        {
          '<leader>ql',
          function()
            require('persistence').load { last = true }
          end,
          desc = 'Load last session',
        },
        {
          '<leader>qd',
          function()
            require('persistence').stop()
          end,
          desc = 'Stop session saving',
        },
      },
    },
  },

  {
    'akinsho/toggleterm.nvim',
    version = '*',
    config = function()
      require('toggleterm').setup {
        size = function(term)
          if term.direction == 'horizontal' then
            return 15
          elseif term.direction == 'vertical' then
            return vim.o.columns * 0.4 -- 40% of screen width
          end
        end,
        open_mapping = [[<C-\>]], -- Default toggle with Ctrl+\
        hide_numbers = true,
        shade_terminals = false,
        start_in_insert = true,
        insert_mappings = true,
        terminal_mappings = true,
        persist_size = true,
        direction = 'vertical', -- Opens to the right
        close_on_exit = true,
        shell = vim.o.shell,
      }

      -- Simple keymap to toggle terminal
      vim.keymap.set('n', '<leader>tt', '<cmd>ToggleTerm direction=vertical<CR>', { desc = 'Toggle Terminal (Right)' })
      vim.keymap.set('t', '<leader>tt', '<cmd>ToggleTerm<CR>', { desc = 'Toggle Terminal (Right)' })

      -- Optional: Add a horizontal terminal toggle too
      vim.keymap.set('n', '<leader>th', '<cmd>ToggleTerm direction=horizontal<CR>', { desc = 'Toggle Terminal (Bottom)' })
    end,
  },

  -- Fugitive plugin
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

  {
    'folke/trouble.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {},
    cmd = 'Trouble',
    keys = {
      {
        '<leader>xx',
        '<cmd>Trouble diagnostics toggle<cr>',
        desc = 'Diagnostics (Trouble)',
      },
      {
        '<leader>xX',
        '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
        desc = 'Buffer Diagnostics (Trouble)',
      },
      {
        '<leader>cs',
        '<cmd>Trouble symbols toggle focus=false<cr>',
        desc = 'Symbols (Trouble)',
      },
      {
        '<leader>cl',
        '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
        desc = 'LSP Definitions / references / ... (Trouble)',
      },
      {
        '<leader>xL',
        '<cmd>Trouble loclist toggle<cr>',
        desc = 'Location List (Trouble)',
      },
      {
        '<leader>xQ',
        '<cmd>Trouble qflist toggle<cr>',
        desc = 'Quickfix List (Trouble)',
      },
    },
  },
  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local harpoon = require 'harpoon'
      harpoon:setup {}

      -- basic telescope configuration
      local conf = require('telescope.config').values
      local function toggle_telescope(harpoon_files)
        local file_paths = {}
        for _, item in ipairs(harpoon_files.items) do
          table.insert(file_paths, item.value)
        end

        require('telescope.pickers')
          .new({}, {
            prompt_title = 'Harpoon',
            finder = require('telescope.finders').new_table {
              results = file_paths,
            },
            previewer = conf.file_previewer {},
            sorter = conf.generic_sorter {},
          })
          :find()
      end

      vim.keymap.set('n', '<C-e>', function()
        toggle_telescope(harpoon:list())
      end, { desc = 'Open harpoon window' })
      vim.keymap.set('n', '<leader>ha', function()
        harpoon:list():add()
      end, { desc = '[A]dd to harpoon' })
      vim.keymap.set('n', '<C-S-P>', function()
        harpoon:list():prev()
      end)
      vim.keymap.set('n', '<C-S-N>', function()
        harpoon:list():next()
      end)
      vim.keymap.set('n', '<leader>hc', function()
        harpoon:list():clear()
      end, { desc = '[C]lear harpoon' })
    end,
  },
  {
    'linux-cultist/venv-selector.nvim',
    dependencies = {
      'neovim/nvim-lspconfig',
      { 'nvim-telescope/telescope.nvim', branch = '0.1.x', dependencies = { 'nvim-lua/plenary.nvim' } }, -- optional: you can also use fzf-lua, snacks, mini-pick instead.
    },
    ft = 'python', -- Load when opening Python files
    keys = {
      -- { ',v', '<cmd>VenvSelect<cr>' }, -- Open picker on keymap
    },
    opts = { -- this can be an empty lua table - just showing below for clarity.
      search = {}, -- if you add your own searches, they go here.
      options = {}, -- if you add plugin options, they go here.
    },
  },
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    build = 'cd app && yarn install',
    init = function()
      vim.g.mkdp_filetypes = { 'markdown' }
    end,
    ft = { 'markdown' },
  },
  {
    '3rd/image.nvim',
    opts = {
      backend = 'kitty', -- or "ueberzug" or "sixel"
      processor = 'magick_cli', -- or "magick_rock"
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
          only_render_image_at_cursor_mode = 'popup', -- or "inline"
          floating_windows = false, -- if true, images will be rendered in floating markdown windows
          filetypes = { 'markdown', 'vimwiki' }, -- markdown extensions (ie. quarto) can go here
        },
        neorg = {
          enabled = true,
          filetypes = { 'norg' },
        },
        typst = {
          enabled = true,
          filetypes = { 'typst' },
        },
        html = {
          enabled = false,
        },
        css = {
          enabled = false,
        },
      },

      scale_factor = 1.0,
      max_width = 100, -- tweak to preference
      max_height = 12, -- ^
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
      window_overlap_clear_enabled = true, -- toggles images when windows are overlapped
      window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', 'snacks_notif', 'scrollview', 'scrollview_sign' },
      editor_only_render_when_focused = false, -- auto show/hide images when the editor gains/looses focus
      tmux_show_only_in_active_window = false, -- auto show/hide images in the correct Tmux window (needs visual-activity off)
      hijack_file_patterns = { '*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.avif' }, -- render image files as images when opened
    },
  },
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
    'uga-rosa/ccc.nvim',
    cmd = { 'CccPick', 'CccConvert', 'CccHighlighterToggle' },
    keys = {
      { '<leader>cp', '<cmd>CccPick<cr>', desc = 'Color picker' },
      { '<leader>cc', '<cmd>CccConvert<cr>', desc = 'Convert color' },
      { '<leader>ct', '<cmd>CccHighlighterToggle<cr>', desc = 'Toggle highlighter' },
    },
    config = function()
      local ccc = require 'ccc'
      ccc.setup {
        highlighter = {
          auto_enable = true,
          lsp = true,
          excludes = { 'lazy', 'mason', 'help', 'neo-tree' },
        },
        pickers = {
          ccc.picker.hex,
          ccc.picker.css_rgb,
          ccc.picker.css_hsl,
          ccc.picker.css_hwb,
        },
        alpha_show = 'auto',
        recognize = { input = true, output = true },
        inputs = { ccc.input.rgb, ccc.input.hsl, ccc.input.cmyk },
        outputs = {
          ccc.output.hex,
          ccc.output.css_rgb,
          ccc.output.css_hsl,
        },
      }
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

  {
    'cenk1cenk2/schema-companion.nvim',
    dependencies = {
      { 'nvim-lua/plenary.nvim' },
    },
    config = function()
      require('schema-companion').setup {
        log_level = vim.log.levels.INFO,
      }
    end,
  },
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = true,
    -- use opts = {} for passing setup options
    -- this is equivalent to setup({}) function
  },
  -- {
  --   'catgoose/nvim-colorizer.lua',
  --   event = 'VeryLazy',
  --   opts = {
  --     lazy_load = true,
  --     filetypes = {
  --       'css',
  --       'javascriptreact',
  --       'typescriptreact',
  --     },
  --   },
  -- },
  -- {
  --   'piersolenski/import.nvim',
  --   dependencies = {
  --     -- One of the following pickers is required:
  --     'nvim-telescope/telescope.nvim',
  --     -- 'folke/snacks.nvim',
  --     -- 'ibhagwan/fzf-lua',
  --   },
  --   opts = {
  --     picker = 'telescope',
  --   },
  --   keys = {
  --     {
  --       '<leader>si',
  --       function()
  --         require('import').pick()
  --       end,
  --       desc = '[S]earch [I]mports',
  --     },
  --   },
  -- },

  -- The following comments only work if you have downloaded the kickstart repo, not just copy pasted the
  -- init.lua. If you want these files, they are in the repository, so you can just download them and
  -- place them in the correct locations.

  -- NOTE: Next step on your Neovim journey: Add/Configure additional plugins for Kickstart
  --
  --  Here are some example plugins that I've included in the Kickstart repository.
  --  Uncomment any of the lines below to enable them (you will need to restart nvim).
  --
  -- require 'kickstart.plugins.debug',
  -- require 'kickstart.plugins.indent_line',
  -- require 'kickstart.plugins.lint',
  -- require 'kickstart.plugins.autopairs',
  -- require 'kickstart.plugins.neo-tree',
  -- require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps

  -- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
  --    This is the easiest way to modularize your config.
  --
  --  Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
  -- { import = 'custom.plugins' },
  --
  -- For additional information with loading, sourcing and examples see `:help lazy.nvim-🔌-plugin-spec`
  -- Or use telescope!
  -- In normal mode type `<space>sh` then write `lazy.nvim-plugin`
  -- you can continue same window with `<space>sr` which resumes last telescope search
}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
