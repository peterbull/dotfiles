local M = {}

local rdbg = vim.fn.exepath 'rdbg'

M.adapters = {
  ruby = {
    type = 'server',
    host = '127.0.0.1',
    port = '${port}',
    executable = {
      command = rdbg,
      args = { '--open', '--port', '${port}', '--host', '127.0.0.1', '-c', '--' },
    },
  },
}

M.configurations = {
  {
    name = 'Launch Current Ruby File',
    type = 'ruby',
    request = 'attach', -- attach to the rdbg server that executable spins up
    port = '${port}',
    host = '127.0.0.1',
    program = '${file}',
    command = { 'ruby', '${file}' },
  },
  {
    name = 'Rails Server',
    type = 'ruby',
    request = 'attach',
    port = '${port}',
    host = '127.0.0.1',
    command = { 'bin/rails', 'server' },
    cwd = '${workspaceFolder}',
  },
  {
    name = 'Attach to rdbg',
    type = 'ruby',
    request = 'attach',
    port = 38698,
    host = '127.0.0.1',
  },
}

return M
