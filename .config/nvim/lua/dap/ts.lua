local M = {}

M.adapters = {
  ['pwa-node'] = {
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
  },

  ['node'] = function(cb, config)
    if config.type == 'node' then
      config.type = 'pwa-node'
    end
    local native = M.adapters['pwa-node']
    if type(native) == 'function' then
      native(cb, config)
    else
      cb(native)
    end
  end,
  ['pwa-chrome'] = {
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
  },
}

M.configurations = {
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
  {
    type = 'pwa-chrome',
    request = 'launch',
    name = 'Launch Chrome (debug profile)',
    url = 'http://app.ctmdev.us',
    runtimeExecutable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    webRoot = '${workspaceFolder}',
    userDataDir = vim.fn.expand '~/.config/chrome-debug',
    cwd = '${workspaceFolder}',
  },
  {
    type = 'pwa-chrome',
    request = 'attach',
    name = 'Attach to Chrome (pick remote-debugging port)',
    url = function()
      return 'http://localhost:' .. (_G.__dap_chrome_last_port or 9222)
    end,
    webRoot = '${workspaceFolder}',
    port = function()
      return _G.__dap_chrome_last_port or 9222
    end,
    cwd = '${workspaceFolder}',
  },
}

-- Async, fuzzy-finder-friendly port prompt. Call this from a keymap/command
-- BEFORE starting the DAP session for any of the Chrome configs above.
-- Uses vim.ui.select, so it'll route through Telescope/fzf-lua/snacks if
-- you've registered one of those as your vim.ui.select handler.
function M.pick_port_and_launch(config_name)
  local dap = require 'dap'

  local common_ports = { '9222', '9229', '9230', 'Custom…' }

  vim.ui.select(common_ports, { prompt = 'Remote debugging port:' }, function(choice)
    if not choice then
      return
    end

    local function start_with_port(port)
      _G.__dap_chrome_last_port = tonumber(port) or 9222
      -- Find the matching config by name and launch it directly.
      for _, cfg in ipairs(M.configurations) do
        if cfg.name == config_name then
          dap.run(cfg)
          return
        end
      end
    end

    if choice == 'Custom…' then
      -- vim.fn.input here is fine: it's synchronous but we're no longer
      -- inside a DAP config resolver, we're in a UI callback.
      local custom = vim.fn.input('Port: ', '9222')
      start_with_port(custom ~= '' and custom or '9222')
    else
      start_with_port(choice)
    end
  end)
end

return M
