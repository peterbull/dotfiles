local M = {}
M.adapters = {
  lldb = require 'dap.checked-adapter' {
    type = 'executable',
    command = vim.fn.stdpath 'data' .. '/mason/packages/codelldb/extension/adapter/codelldb',
    name = 'lldb',
  },
}
return M
