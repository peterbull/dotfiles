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
}

return M
