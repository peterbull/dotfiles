local M = {}
local tools = vim.fn.stdpath 'config' .. '/tools/sorbet'

local function capture_project(root)
  return root and vim.uv.fs_stat(root .. '/app/classes/live_conversation_capture/state.rb') ~= nil
end

local function repo_config(root)
  return root and vim.uv.fs_stat(root .. '/sorbet/config') ~= nil
end

---@param root string
---@param name string
---@param config_file string
---@return boolean
local function configured_file(root, name, config_file)
  local has_inputs = false
  for _, line in ipairs(vim.fn.readfile(config_file)) do
    line = vim.trim(line)
    local input = line:match '^%-%-file=(.+)$' or line:match '^%-%-dir=(.+)$'
    if not input and line ~= '' and not line:match '^[#%-]' then
      input = line
    end
    if input then
      has_inputs = true
      local path = vim.fs.normalize(input:sub(1, 1) == '/' and input or root .. '/' .. input)
      if name == path or vim.startswith(name, path .. '/') then
        return true
      end
    end
  end
  return not has_inputs
end

---@param bufnr integer
---@param on_dir fun(root: string)
function M.root_dir(bufnr, on_dir)
  -- Diffview and fugitive buffers hold older revisions; Sorbet would read them as duplicate definitions.
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name:match '^%a[%w+.-]*://' or not vim.uv.fs_stat(name) then
    return
  end

  local path = vim.fs.dirname(name)
  local config_file = vim.fs.find('sorbet/config', { path = path, upward = true, type = 'file' })[1]
  if config_file then
    local root = vim.fs.dirname(vim.fs.dirname(config_file))
    -- Sorbet can crash when LSP opens a file outside its configured input directory.
    if configured_file(root, name, config_file) then
      on_dir(root)
    end
    return
  end

  local gemfile = vim.fs.find('Gemfile', { path = path, upward = true, type = 'file' })[1]
  local root = gemfile and vim.fs.dirname(gemfile)
  if capture_project(root) and configured_file(root, name, tools .. '/phonetrac.config') then
    on_dir(root)
  end
end

function M.cmd(dispatchers, config)
  local command = { 'mise', 'exec', '--', 'bundle', 'exec' }
  if repo_config(config.root_dir) then
    vim.list_extend(command, { 'srb', 'tc', '--lsp' })
  elseif capture_project(config.root_dir) then
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
