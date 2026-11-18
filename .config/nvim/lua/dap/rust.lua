local M = {}

-- Reads binary targets from cargo metadata, so workspaces (whose root Cargo.toml has no package name) resolve too.
local function cargo_binaries()
  local result = vim.system({ 'cargo', 'metadata', '--no-deps', '--format-version', '1' }, { text = true }):wait()
  if result.code ~= 0 then
    vim.notify('cargo metadata failed: ' .. result.stderr, vim.log.levels.ERROR)
    return nil
  end

  local metadata = vim.json.decode(result.stdout)
  local binaries = {}
  for _, package in ipairs(metadata.packages) do
    for _, target in ipairs(package.targets) do
      if vim.tbl_contains(target.kind, 'bin') then
        table.insert(binaries, target.name)
      end
    end
  end
  return binaries, metadata.target_directory
end

local function rust_package()
  local dap = require 'dap'
  local result = vim.fn.system { 'cargo', 'build' }
  if vim.v.shell_error ~= 0 then
    vim.notify('Cargo build failed: ' .. result, vim.log.levels.ERROR)
    return dap.ABORT
  end

  local binaries, target_directory = cargo_binaries()
  if not binaries then
    return dap.ABORT
  end
  if #binaries == 0 then
    vim.notify('No binary targets in this Cargo project', vim.log.levels.ERROR)
    return dap.ABORT
  end

  local binary = binaries[1]
  if #binaries > 1 then
    binary = require('dap.utils').pick_one(binaries, 'Binary to debug: ', function(name)
      return name
    end)
    if not binary then
      return dap.ABORT
    end
  end
  return target_directory .. '/debug/' .. binary
end
local function rust_file()
  local current_file = vim.fn.expand '%:p'
  local file_name = vim.fn.expand '%:t:r'
  local exe_path = vim.fn.getcwd() .. '/target/debug/' .. file_name

  vim.fn.mkdir(vim.fn.getcwd() .. '/target/debug', 'p')

  local result = vim.fn.system { 'rustc', '-g', '--edition', '2021', '-o', exe_path, current_file }

  if vim.v.shell_error ~= 0 then
    vim.notify('Rust compile failed: ' .. result, vim.log.levels.ERROR)
    return require('dap').ABORT
  end

  return exe_path
end

local rust_prettifier_file = vim.fn.expand '~/peter-projects/rust-prettifier-for-lldb/rust_prettifier_for_lldb.py'
local rust_prettifier_init
if vim.fn.filereadable(rust_prettifier_file) == 1 then
  rust_prettifier_init = 'command script import "' .. vim.fn.escape(rust_prettifier_file, '\\"') .. '"'
end
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
