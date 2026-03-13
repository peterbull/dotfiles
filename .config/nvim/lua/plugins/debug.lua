return {
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
            name = 'Launch: Current File (root venv)',
            type = 'python',
            request = 'launch',
            program = '${file}',
            pythonPath = function()
              local cwd = vim.fn.getcwd()
              local venv = cwd .. '/.venv/bin/python'
              if vim.fn.executable(venv) == 1 then
                return venv
              end
              return 'python3'
            end,
            justMyCode = false,
            showReturnValue = true,
          })
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
                localRoot = (function()
                  local cwd = vim.fn.getcwd()
                  -- if airflow is in the path we are in the airflow dir
                  if string.find(cwd:lower(), 'airflow') then
                    return cwd
                  else
                    -- otherwise we need to fix the path
                    return cwd .. '/airflow'
                  end
                end)(),
                remoteRoot = '/opt/airflow',
              },
            },
            justMyCode = false,
            showReturnValue = true,
          })
          table.insert(dap.configurations.python, {
            name = 'Docker: fuel firebase functions',
            type = 'python',
            request = 'attach',
            connect = {
              port = 5679,
              host = 'localhost',
            },
            pathMappings = {
              {
                localRoot = vim.fn.getcwd(),
                remoteRoot = '/srv/firebase/functions/python',
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
        '<leader>dh',
        function()
          require('dap').set_breakpoint(nil, vim.fn.input 'Breakpoint hit number: ')
        end,
        desc = 'Breakpoint Hit Condition',
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
        '<leader>dk',
        function()
          require('dap').down()
        end,
        desc = 'Down',
      },
      {
        '<leader>dj',
        function()
          require('dap').up()
        end,
        desc = 'Up',
      },
      {
        '<F4>',
        function()
          require('dap').down()
        end,
        desc = 'Down',
      },
      {
        '<F3>',
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
      -- {
      --   '<leader>dr',
      --   function()
      --     require('dap').repl.toggle()
      --   end,
      --   desc = 'Toggle REPL',
      -- },

      {
        '<leader>dr',
        function()
          require('dap').repl.toggle({}, 'botright vsplit')
        end,
        desc = 'Toggle REPL (right vertical split)',
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
        '<leader>dsi',
        function()
          require('dap').up()
        end,
        desc = 'Debug: DAP Stack UP',
      },
      {
        '<leader>dso',
        function()
          require('dap').down()
        end,
        desc = 'Debug: DAP Stack DOWN',
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

      -- logs
      dap.set_log_level 'INFO'

      -- node
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

      -- node (compat w/ vscode naming)
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

      -- chrome
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

      -- lldb
      dap.adapters.lldb = {
        type = 'executable',
        command = vim.fn.stdpath 'data' .. '/mason/packages/codelldb/extension/adapter/codelldb',
        name = 'lldb',
      }
      dap.adapters.codelldb = dap.adapters.lldb

      -- bash
      dap.adapters.sh = {
        type = 'executable',
        command = vim.fn.stdpath 'data' .. '/mason/bin/bash-debug-adapter',
        name = 'sh',
      }
      -- go
      dap.adapters.go = {
        type = 'server',
        port = '${port}',
        executable = {
          command = vim.fn.stdpath 'data' .. '/mason/bin/dlv',
          args = { 'dap', '-l', '127.0.0.1:${port}' },
        },
      }

      dap.configurations.go = {
        {
          type = 'go',
          name = 'Debug Current File',
          request = 'launch',
          program = '${file}',
        },
        {
          type = 'go',
          name = 'Debug Package',
          request = 'launch',
          program = '${fileDirname}',
        },
        {
          type = 'go',
          name = 'Debug Main Package',
          request = 'launch',
          program = '${workspaceFolder}',
        },
        {
          type = 'go',
          name = 'Debug with Args',
          request = 'launch',
          program = '${workspaceFolder}',
          args = function()
            local args_str = vim.fn.input 'Arguments: '
            return vim.split(args_str, ' ')
          end,
        },
        {
          type = 'go',
          name = 'Debug Test (Current File)',
          request = 'launch',
          mode = 'test',
          program = '${file}',
        },
        {
          type = 'go',
          name = 'Debug Test (Package)',
          request = 'launch',
          mode = 'test',
          program = '${fileDirname}',
        },
        {
          type = 'go',
          name = 'Attach to Process',
          mode = 'local',
          request = 'attach',
          processId = require('dap.utils').pick_process,
        },
      }

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
      vscode.type_to_filetypes['go'] = { 'go' }
      vscode.type_to_filetypes['delve'] = { 'go' }
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
            request = 'launch',
            name = 'Debug Current File (tsx with .env.local)',
            runtimeExecutable = vim.fn.getcwd() .. '/node_modules/.bin/tsx',
            runtimeArgs = { '--env-file', '.env.local' },
            args = { '${file}' },
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
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

            local function find_root(marker, start_path)
              local path = start_path or vim.fn.getcwd()
              while path ~= '/' do
                if vim.fn.filereadable(path .. '/' .. marker) == 1 then
                  return path
                end
                path = vim.fn.fnamemodify(path, ':h')
              end
              return nil
            end

            if extension == 'c' then
              -- search from the current file's directory, not cwd
              local file_dir = vim.fn.expand '%:p:h'
              local root = find_root('Makefile', file_dir)
              if not root then
                vim.notify('No Makefile found', vim.log.levels.ERROR)
                return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/build/', 'file')
              end
              vim.notify('Building in: ' .. root, vim.log.levels.INFO)
              local result = vim.fn.system('make -C ' .. root)
              if vim.v.shell_error ~= 0 then
                vim.notify('Build failed: ' .. result, vim.log.levels.ERROR)
                return vim.fn.input('Path to executable: ', root .. '/build/', 'file')
              end
              return root .. '/build/main'
            end

            if extension == 'rs' then
              local file_dir = vim.fn.expand '%:p:h'
              local root = find_root('Cargo.toml', file_dir)
              if not root then
                vim.notify('No Cargo.toml found', vim.log.levels.ERROR)
                return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
              end
              local result = vim.fn.system('cargo build --manifest-path ' .. root .. '/Cargo.toml')
              if vim.v.shell_error ~= 0 then
                vim.notify('Build failed: ' .. result, vim.log.levels.ERROR)
                return vim.fn.input('Path to executable: ', root .. '/target/debug/', 'file')
              end
              local package_name = get_rust_package_name() or 'backend'
              return root .. '/target/debug/' .. package_name
            end

            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
      }
      local function rust_package()
        local result = vim.fn.system 'cargo build'
        if vim.v.shell_error ~= 0 then
          vim.notify('Cargo build failed: ' .. result, vim.log.levels.ERROR)
          return nil
        end

        local package_name = get_rust_package_name() or 'backend'
        local exe_path = vim.fn.getcwd() .. '/target/debug/' .. package_name
        return exe_path
      end
      local function rust_file()
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
      end

      -- https://github.com/cmrschwarz/rust-prettifier-for-lldb
      -- lldb doesn't have great rust prettification support ootb
      -- clone the repo somewhere and point to it here to use it instead
      local rust_prettifier_file = '/Users/peterbull/peter-projects/rust-prettifier-for-lldb/rust_prettifier_for_lldb.py'
      local rust_prettifier_init = 'command script import ' .. rust_prettifier_file

      dap.configurations.rust = {
        {
          name = 'Launch Rust Workspace',
          type = 'lldb',
          request = 'launch',
          program = rust_package,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          expressions = 'simple',
          initCommands = {
            rust_prettifier_init,
          },
          args = {},
        },
        {
          name = 'Launch Rust Workspace - Reef',
          type = 'lldb',
          request = 'launch',
          program = rust_package,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          expressions = 'simple',
          initCommands = {
            rust_prettifier_init,
          },
          args = { 'tokenize', vim.fn.getcwd() .. '/reef/hello.reef' },
        },
        {
          name = 'Launch Rust Workspace - Reef - REPL',
          type = 'lldb',
          request = 'launch',
          program = rust_package,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          expressions = 'simple',
          initCommands = {
            rust_prettifier_init,
          },
          args = { 'repl' },
        },
        {
          name = 'Launch Rust Current File',
          type = 'lldb',
          request = 'launch',
          program = rust_file,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          expressions = 'simple',
          initCommands = {
            rust_prettifier_init,
          },
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
        {
          name = 'Launch Zig Current File -r (main.zig)',
          type = 'lldb',
          request = 'launch',
          program = function()
            local cwd = vim.fn.getcwd()
            local target_dir

            -- if we're in the project root (has build.zig)
            if vim.fn.filereadable(cwd .. '/build.zig') == 1 then
              target_dir = cwd

            -- if we're in parent dir, find a subdir with build.zig
            else
              local build_files = vim.fn.glob(cwd .. '/*/build.zig', false, true)

              if #build_files == 0 then
                vim.notify('No Zig project found in subdirectories', vim.log.levels.ERROR)
                return nil
              elseif #build_files == 1 then
                -- only one project, use it
                target_dir = vim.fn.fnamemodify(build_files[1], ':h')
              else
                -- multiple projects, prompt to pick
                local choices = vim.tbl_map(function(p)
                  return vim.fn.fnamemodify(p, ':h:t')
                end, build_files)

                local choice = vim.fn.inputlist(vim.list_extend(
                  { 'Select Zig project:' },
                  vim.tbl_map(function(i, v)
                    return i .. '. ' .. v
                  end, ipairs(choices))
                ))

                if choice < 1 or choice > #build_files then
                  vim.notify('Invalid selection', vim.log.levels.ERROR)
                  return nil
                end
                target_dir = vim.fn.fnamemodify(build_files[choice], ':h')
              end
            end

            -- build from target_dir
            local result = vim.fn.system('zig build -Doptimize=Debug --build-file ' .. target_dir .. '/build.zig')
            if vim.v.shell_error ~= 0 then
              vim.notify('Zig build failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            local project_name = vim.fn.fnamemodify(target_dir, ':t')
            project_name = string.gsub(project_name, '-', '_')
            return target_dir .. '/zig-out/bin/' .. project_name
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
              ['go'] = { 'go' },
              ['delve'] = { 'go' },
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
          ['go'] = { 'go' },
          ['delve'] = { 'go' },
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
