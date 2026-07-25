local M = {}

---Find the project root by walking up from start_path looking for marker
---@param marker string
---@param start_path string
---@return string|nil
local function find_root(marker, start_path)
  local path = start_path or vim.fn.getcwd()
  while path ~= '/' do
    if vim.fn.filereadable(path .. '/' .. marker) == 1 then
      return path
    end
    path = vim.fn.fnamemodify(path, ':h')
  end
  return nil
end

---Build via Makefile + Docker (Linux ELF64).
---@return string|nil executable path
local function build_via_makefile()
  local file_dir = vim.fn.expand '%:p:h'
  local root = find_root('Makefile', file_dir)
  if not root then
    vim.notify('No Makefile found', vim.log.levels.ERROR)
    return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/out/', 'file')
  end
  vim.notify('Running make in: ' .. root, vim.log.levels.INFO)
  local result = vim.fn.system('make -C ' .. vim.fn.shellescape(root) .. ' build 2>&1')
  if vim.v.shell_error ~= 0 then
    vim.notify('Build failed:\n' .. result, vim.log.levels.ERROR)
    return vim.fn.input('Path to executable: ', root .. '/out/', 'file')
  end
  vim.notify(result, vim.log.levels.INFO)
  local exe = root .. '/out/base'
  if vim.fn.executable(exe) == 0 then
    return vim.fn.input('Path to executable: ', root .. '/out/', 'file')
  end
  return exe
end

-- =====================================================================
-- GDB adapter  (cpptools → Docker GDB, for Linux ELF debugging)
-- =====================================================================
-- Requires: mason package cpptools  (run :DapInstall cpptools)
M.adapters = {
  asm_gdb = {
    type = 'executable',
    command = vim.fn.stdpath 'data' .. '/mason/packages/cpptools/extension/debugAdapters/bin/OpenDebugAD7',
    name = 'asm_gdb',
  },
}

M.configurations = {
  -- ---------------------------------------------------------------
  -- Linux ELF debugging via GDB inside Docker  (the real thing)
  -- ---------------------------------------------------------------
  {
    name = 'ASM: Launch (Makefile, GDB)',
    type = 'asm_gdb',
    request = 'launch',
    program = build_via_makefile,
    cwd = '${workspaceFolder}',
    stopAtEntry = true,
    MIMode = 'gdb',
    miDebuggerPath = vim.fn.expand '~/peter-projects/triode/asm/x86-64-linux/gdb-docker.sh',
    setupCommands = {
      {
        text = 'set disassembly-flavor intel',
        description = 'Use Intel syntax for disassembly',
      },
    },
  },
  {
    name = 'ASM: Launch (manual path, GDB)',
    type = 'asm_gdb',
    request = 'launch',
    program = function()
      return vim.fn.input('Path to ELF executable: ', vim.fn.getcwd() .. '/out/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopAtEntry = true,
    MIMode = 'gdb',
    miDebuggerPath = vim.fn.expand '~/peter-projects/triode/asm/x86-64-linux/gdb-docker.sh',
    setupCommands = {
      { text = 'set disassembly-flavor intel' },
    },
  },
  -- ---------------------------------------------------------------
  -- codelldb (local macOS macho64) — quick-iteration convenience.
  -- NOTE: Linux syscalls will NOT work correctly on macOS
  -- (different syscall numbers & ABI).  Use the GDB config above
  -- for real Linux debugging.  This is useful for algorithmic /
  -- computation-heavy assembly that doesn't do raw syscalls.
  -- ---------------------------------------------------------------
  {
    name = 'ASM: Launch (local macho64, lldb)',
    type = 'lldb',
    request = 'launch',
    program = function()
      local src = vim.fn.expand '%:p'
      local out_dir = vim.fn.expand '%:p:h' .. '/out-local'
      local name = vim.fn.expand '%:t:r'
      local obj = out_dir .. '/' .. name .. '.o'
      local exe = out_dir .. '/' .. name

      vim.fn.mkdir(out_dir, 'p')

      local nasm_cmd = string.format('nasm -f macho64 -g %s -o %s', vim.fn.shellescape(src), vim.fn.shellescape(obj))
      local result = vim.fn.system(nasm_cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify('NASM failed:\n' .. result, vim.log.levels.ERROR)
        return nil
      end

      local sdk_path = vim.fn.system 'xcrun --show-sdk-path 2>/dev/null'
      sdk_path = vim.trim(sdk_path)
      if sdk_path == '' then
        sdk_path = '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'
      end

      local ld_cmd = string.format(
        'ld -lSystem -L%s/usr/lib -macos_version_min 11.0 -no_pie -e _start %s -o %s',
        vim.fn.shellescape(sdk_path),
        vim.fn.shellescape(obj),
        vim.fn.shellescape(exe)
      )
      result = vim.fn.system(ld_cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify('LD failed:\n' .. result, vim.log.levels.ERROR)
        return nil
      end

      vim.notify('Built: ' .. exe .. '  (macOS macho64 — Linux syscalls will NOT work)', vim.log.levels.WARN)
      return exe
    end,
    cwd = '${fileDirname}',
    stopOnEntry = true,
    args = {},
    -- Suppress EXC_SYSCALL on macOS — raw Linux syscalls are invalid here.
    initCommands = {
      'process handle --stop false --pass true --notify false SIGSYS',
    },
  },
}

return M
