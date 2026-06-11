local M = {}
M.adapters = {
  sh = {
    type = 'executable',
    command = vim.fn.stdpath 'data' .. '/mason/bin/bash-debug-adapter',
    name = 'sh',
  },
}

M.configurations = {
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

return M
