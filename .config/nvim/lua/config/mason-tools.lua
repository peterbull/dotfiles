local M = {}

function M.ensure_installed()
  local tools = { 'stylua', 'prettier', 'black', 'isort', 'shfmt', 'yaml-language-server' }
  -- The configured debugger group is optional; set this false before loading LSP to skip provisioning it.
  if vim.g.dotfiles_dap_tools ~= false then
    vim.list_extend(tools, { 'debugpy', 'bash-debug-adapter', 'js-debug-adapter', 'codelldb', 'delve', 'cpptools' })
  end
  return tools
end

return M
