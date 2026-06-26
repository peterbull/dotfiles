return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'jbyuki/one-small-step-for-vimkind',
      'nvim-neotest/nvim-nio',
      { 'saghen/blink.compat', version = '*', lazy = true, opts = {} },
      'rcarriga/cmp-dap',
      { 'theHamsta/nvim-dap-virtual-text', opts = {} },
      {
        'mfussenegger/nvim-dap-python',
        ft = 'python',
        config = function()
          require('dap-python').setup 'python3'

          local dap = require 'dap'
          local py = require 'dap.python'

          dap.adapters.python = py.adapters.python

          for _, conf in ipairs(py.configurations.python) do
            table.insert(dap.configurations.python, conf)
          end
        end,
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
            'delve',
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

    keys = require('dap.keys').keys,

    config = function()
      local dap = require 'dap'
      dap.set_log_level 'INFO'

      -- lldb
      local lldb_config = require 'dap.lldb'
      dap.adapters.lldb = lldb_config.adapters.lldb
      dap.adapters.codelldb = dap.adapters.lldb

      -- go
      local go_config = require 'dap.go'
      dap.adapters.go = go_config.adapters.go
      dap.configurations.go = go_config.configurations

      -- lua
      local lua_config = require 'dap.lua'
      dap.configurations.lua = lua_config.configurations.lua
      dap.adapters.nlua = lua_config.adapters.nlua

      -- ts
      local ts_configs = require 'dap.ts'
      dap.adapters['pwa-node'] = ts_configs.adapters['pwa-node']
      dap.adapters['node'] = ts_configs.adapters['node']
      dap.adapters['pwa-chrome'] = ts_configs.adapters['pwa-chrome']

      -- Setup vscode compatibility
      local js_filetypes = { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' }
      local vscode = require 'dap.ext.vscode'
      vscode.type_to_filetypes['node'] = js_filetypes
      vscode.type_to_filetypes['pwa-node'] = js_filetypes
      vscode.type_to_filetypes['pwa-chrome'] = js_filetypes
      vscode.type_to_filetypes['lldb'] = { 'c', 'cpp', 'rust', 'zig' }
      vscode.type_to_filetypes['codelldb'] = { 'c', 'cpp', 'rust', 'zig' }
      vscode.type_to_filetypes['sh'] = { 'sh', 'bash' }
      vscode.type_to_filetypes['go'] = { 'go' }
      vscode.type_to_filetypes['delve'] = { 'go' }
      vscode.type_to_filetypes['ruby'] = { 'ruby' }

      -- Setup JavaScript/TypeScript configurations
      for _, language in ipairs(js_filetypes) do
        dap.configurations[language] = ts_configs.configurations
      end

      -- C config
      local c_config = require 'dap.c'
      dap.configurations.c = c_config.configurations
      dap.configurations.cpp = dap.configurations.c

      -- rust
      local rust_config = require 'dap.rust'
      dap.configurations.rust = rust_config.configurations

      -- zig
      local zig_config = require 'dap.zig'
      dap.configurations.zig = zig_config.configurations

      -- ruby
      local ruby_config = require 'dap.ruby'
      ruby_config.setup()
      -- sh
      local sh_config = require 'dap.sh'
      dap.adapters.sh = sh_config.adapters.sh
      dap.configurations.sh = sh_config.configurations
      dap.configurations.bash = dap.configurations.sh

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
    opts = {
      element_mappings = {
        stacks = {
          open = '<CR>',
          expand = 'o',
        },
      },
    },
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
}
