local M = {}

M.adapters = {
  go = {
    type = 'server',
    port = '${port}',
    executable = {
      command = vim.fn.stdpath 'data' .. '/mason/bin/dlv',
      args = { 'dap', '-l', '127.0.0.1:${port}' },
    },
  },
}
-- https://go.googlesource.com/vscode-go/+/c3516da303907ca11ee51e64f961cf2a4ac5339a/docs/dlv-dap.md
M.configurations = {

  {
    type = 'go',
    name = 'Debug Current File',
    request = 'launch',
    program = '${file}',
    outputMode = 'remote',
    showGlobalVariables = true,
    mode = 'debug',
  },
  {
    type = 'go',
    name = 'Debug Package',
    request = 'launch',
    program = '${fileDirname}',
    outputMode = 'remote',
  },
  {
    type = 'go',
    name = 'Debug Package for vessel',
    request = 'launch',
    program = '${fileDirname}',
    outputMode = 'remote',
    args = { 'run', 'ubuntu', '/bin/sh', '--', '-c', '"echo hello"' },
  },
  {
    type = 'go',
    name = 'Debug Main Package',
    request = 'launch',
    program = '${workspaceFolder}',
    outputMode = 'remote',
  },
  {
    type = 'go',
    name = 'Debug with Args',
    request = 'launch',
    program = '${workspaceFolder}',
    outputMode = 'remote',
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
    outputMode = 'remote',
  },
  {
    type = 'go',
    name = 'Debug Test (Package)',
    request = 'launch',
    mode = 'test',
    program = '${fileDirname}',
    outputMode = 'remote',
  },
  {
    type = 'go',
    name = 'Attach to Process',
    mode = 'local',
    request = 'attach',
    processId = require('dap.utils').pick_process,
    outputMode = 'remote',
  },
}

return M
