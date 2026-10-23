local M = {}
local tools = vim.fn.stdpath 'config' .. '/tools/sorbet'

local function capture_project(root)
  return root and vim.uv.fs_stat(root .. '/app/classes/live_conversation_capture/state.rb') ~= nil
end

function M.root_dir(bufnr, on_dir)
  local path = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  local config_file = vim.fs.find('sorbet/config', { path = path, upward = true, type = 'file' })[1]
  if config_file then
    on_dir(vim.fs.dirname(vim.fs.dirname(config_file)))
    return
  end

  local gemfile = vim.fs.find('Gemfile', { path = path, upward = true, type = 'file' })[1]
  local root = gemfile and vim.fs.dirname(gemfile)
  if capture_project(root) then
    on_dir(root)
  end
end

function M.cmd(dispatchers, config)
  local command = { 'mise', 'exec', '--', 'bundle', 'exec' }
  if capture_project(config.root_dir) then
    vim.list_extend(command, {
      '--gemfile',
      tools .. '/Gemfile',
      'srb',
      'tc',
      '--no-config',
      '@' .. tools .. '/phonetrac.config',
      '--cache-dir=' .. vim.fn.stdpath 'cache' .. '/sorbet/' .. vim.fn.sha256(config.root_dir):sub(1, 12),
      '--lsp',
    })
  else
    vim.list_extend(command, { 'srb', 'tc', '--lsp' })
    if vim.fn.executable 'watchman' == 0 then
      table.insert(command, '--disable-watchman')
    end
  end
  return vim.lsp.rpc.start(command, dispatchers, { cwd = config.root_dir, env = config.cmd_env })
end

return M
