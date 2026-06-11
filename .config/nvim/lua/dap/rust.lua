local M = {}

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

-- M.adapters = {} -- lldb
M.configurations = {
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

return M
