local M = {}
local zig_prettifier_file = '/Users/peterbull/tools/zig/lldb_pretty_printers.py'
local zig_prettifier_init = 'command script import ' .. zig_prettifier_file
local zig_init_commands = {
  zig_prettifier_init,
  'type category enable zig.lang',
  'type category enable zig.std',
  'type format add --format decimal uint8_t',
  'type format add --format decimal "unsigned char"',
}

local function get_target_zig_dir(cwd)
  local target_dir
  -- if we're in the project root (has build.zig)
  if vim.fn.filereadable(cwd .. '/build.zig') == 1 then
    target_dir = cwd
    -- if we're in parent dir, find a subdir with build.zig
  else
    local build_files = vim.fn.glob(cwd .. '/*/build.zig', false, true)

    if #build_files == 0 then
      vim.notify('No Zig project found in subdirectories', vim.log.levels.ERROR)
      return nil
    elseif #build_files == 1 then
      -- only one project, use it
      target_dir = vim.fn.fnamemodify(build_files[1], ':h')
    else
      -- multiple projects, prompt to pick
      local choices = vim.tbl_map(function(p)
        return vim.fn.fnamemodify(p, ':h:t')
      end, build_files)

      local choice = vim.fn.inputlist(vim.list_extend(
        { 'Select Zig project:' },
        vim.tbl_map(function(i, v)
          return i .. '. ' .. v
        end, ipairs(choices))
      ))

      if choice < 1 or choice > #build_files then
        vim.notify('Invalid selection', vim.log.levels.ERROR)
        return nil
      end
      target_dir = vim.fn.fnamemodify(build_files[choice], ':h')
    end
  end
  return target_dir
end
-- M.adapters = {} // lldb
M.configurations = {
  {
    name = 'Launch Zig Workspace',
    type = 'lldb',
    request = 'launch',
    program = function()
      local result = vim.fn.system 'zig build'
      if vim.v.shell_error ~= 0 then
        vim.notify('Zig build failed: ' .. result, vim.log.levels.ERROR)
        return nil
      end

      local exe_path = vim.fn.getcwd() .. '/zig-out/bin/'
      local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
      -- zig renames with underscore on build
      project_name = string.gsub(project_name, '-', '_')
      exe_path = exe_path .. project_name

      return exe_path
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = {},
    initCommands = zig_init_commands,
  },
  {
    name = 'Launch Zig Current File',
    type = 'lldb',
    request = 'launch',
    program = function()
      local current_file = vim.fn.expand '%:p'
      local file_name = vim.fn.expand '%:t:r'
      local exe_path = vim.fn.getcwd() .. '/zig-out/bin/' .. file_name

      vim.fn.system('mkdir -p ' .. vim.fn.getcwd() .. '/zig-out/bin')

      local compile_cmd = string.format('zig build-exe -femit-bin=%s %s', exe_path, current_file)
      local result = vim.fn.system(compile_cmd)

      if vim.v.shell_error ~= 0 then
        vim.notify('Zig compile failed: ' .. result, vim.log.levels.ERROR)
        return nil
      end

      return exe_path
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = {},
    initCommands = zig_init_commands,
  },
  {
    name = 'Launch Zig Current File -r',
    type = 'lldb',
    request = 'launch',
    program = function()
      local cwd = vim.fn.getcwd()
      local target_dir = get_target_zig_dir(cwd)

      local result = vim.fn.system('zig build -Doptimize=Debug --build-file ' .. target_dir .. '/build.zig')
      if vim.v.shell_error ~= 0 then
        vim.notify('Zig build failed: ' .. result, vim.log.levels.ERROR)
        return nil
      end

      local project_name = vim.fn.fnamemodify(target_dir, ':t')
      project_name = string.gsub(project_name, '-', '_')
      return target_dir .. '/zig-out/bin/' .. project_name
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = {},
    initCommands = zig_init_commands,
  },

  {
    name = 'Launch Zig Current File -r --debug-trace',
    type = 'lldb',
    request = 'launch',
    program = function()
      local cwd = vim.fn.getcwd()
      local target_dir = get_target_zig_dir(cwd)

      local result = vim.fn.system('zig build -Doptimize=Debug -freference-trace --build-file ' .. target_dir .. '/build.zig')
      if vim.v.shell_error ~= 0 then
        vim.notify('Zig build failed: ' .. result, vim.log.levels.ERROR)
        return nil
      end

      local project_name = vim.fn.fnamemodify(target_dir, ':t')
      project_name = string.gsub(project_name, '-', '_')
      return target_dir .. '/zig-out/bin/' .. project_name
    end,
    args = { '--debug-trace' },
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    initCommands = zig_init_commands,
  },

  {
    name = 'Launch Zig Current File -r --reef-file --debug-trace',
    type = 'lldb',
    request = 'launch',
    program = function()
      local cwd = vim.fn.getcwd()
      local target_dir = get_target_zig_dir(cwd)

      local result = vim.fn.system('zig build -Doptimize=Debug -freference-trace --build-file ' .. target_dir .. '/build.zig')
      if vim.v.shell_error ~= 0 then
        vim.notify('Zig build failed: ' .. result, vim.log.levels.ERROR)
        return nil
      end

      local project_name = vim.fn.fnamemodify(target_dir, ':t')
      project_name = string.gsub(project_name, '-', '_')
      return target_dir .. '/zig-out/bin/' .. project_name
    end,
    args = { './reef/hello.reef', '--debug-trace' },
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    initCommands = zig_init_commands,
  },
}

return M
