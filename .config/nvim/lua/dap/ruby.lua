local M = {}

local function pick_port()
  local port
  vim.ui.input({ prompt = 'Port to connect to: ' }, function(input)
    port = input
  end)
  return port
end

local function find_cmd_dir(cmd)
  local filepath = vim.fn.getcwd()
  if vim.fn.executable(cmd) == 1 then
    return filepath
  end
  while filepath ~= '' and filepath ~= '/' do
    if vim.fn.executable(filepath .. '/' .. cmd) == 1 then
      return filepath
    end
    filepath = vim.fn.fnamemodify(filepath, ':h')
  end
  error(cmd .. ' not found in ' .. vim.fn.getcwd() .. ' or any ancestor')
end

local function run_cmd(cmd, args, for_current_line, for_current_file, error_on_failure)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  local working_dir = find_cmd_dir(cmd)
  args = args or {}

  if for_current_line then
    table.insert(args, vim.fn.expand '%:p' .. ':' .. vim.fn.line '.')
  elseif for_current_file then
    table.insert(args, vim.fn.expand '%:p')
  end

  local handle
  local pid_or_err
  handle, pid_or_err = vim.loop.spawn(cmd, {
    args = args,
    cwd = working_dir,
    stdio = { nil, stdout, stderr },
  }, function(code)
    if handle then
      handle:close()
    end
    if error_on_failure and code ~= 0 and code ~= 1 then -- ignore rdbg EOF exit
      error('`' .. cmd .. ' ' .. table.concat(args, ' ') .. '` exited with code ' .. code)
    end
  end)

  assert(handle, 'Error running command: ' .. cmd .. tostring(pid_or_err))

  stdout:read_start(function(err, chunk)
    assert(not err, err)
    if chunk then
      vim.schedule(function()
        require('dap.repl').append(chunk)
      end)
    end
  end)
  stderr:read_start(function(err, chunk)
    assert(not err, err)
    if chunk then
      vim.schedule(function()
        require('dap.repl').append('[stderr] ' .. chunk)
      end)
    end
  end)
end

function M.setup()
  local dap = require 'dap'

  dap.adapters.ruby = function(callback, config)
    local server = config.server or vim.env.RUBY_DEBUG_HOST or '127.0.0.1'
    local port = config.port
    port = port or config.random_port and math.random(49152, 65535)
    port = port or pick_port()

    vim.env.RUBY_DEBUG_SHOW_FULL_VALUE = '1'

    if config.command then
      vim.env.RUBY_DEBUG_OPEN = true
      vim.env.RUBY_DEBUG_HOST = server
      vim.env.RUBY_DEBUG_PORT = port
      run_cmd(config.command, config.args, config.current_line, config.current_file, config.error_on_failure)
    end

    vim.defer_fn(function()
      callback { type = 'server', host = server, port = tostring(port) }
    end, config.waiting or 500)
  end

  local base = {
    type = 'ruby',
    request = 'attach',
    options = { source_filetype = 'ruby' },
    error_on_failure = true,
    localfs = true,
  }

  local function attach(config)
    return vim.tbl_extend('force', base, config)
  end

  local function run(config)
    return vim.tbl_extend('force', base, { waiting = 1000, random_port = true }, config)
  end

  dap.configurations.ruby = {
    run { name = 'debug current file', command = 'rdbg', current_file = true },
    run { name = 'run rails', command = 'bundle', args = { 'exec', 'rails', 's' } },
    run { name = 'run rspec current file', command = 'bundle', args = { 'exec', 'rspec' }, current_file = true },
    run { name = 'run rspec current_file:current_line', command = 'bundle', args = { 'exec', 'rspec' }, current_line = true },
    run { name = 'run rspec', command = 'bundle', args = { 'exec', 'rspec' } },
    run { name = 'run minitest current file', command = 'bundle', args = { 'exec', 'ruby', '-Itest' }, current_file = true },
    run { name = 'run rails test current file', command = 'bundle', args = { 'exec', 'rails', 'test' }, current_file = true },
    run { name = 'run rails test current line', command = 'bundle', args = { 'exec', 'rails', 'test' }, current_line = true },

    attach { name = 'attach existing (port 38698)', port = 38698, waiting = 0 },
    attach { name = 'attach existing (pick port)', waiting = 0 },
  }
end

return M
