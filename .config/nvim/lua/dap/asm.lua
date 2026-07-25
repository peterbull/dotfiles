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

---Build an ASM file locally for macOS (macho64) via nasm + ld
---Uses -no_pie to allow absolute text relocations (mov rsi, msg etc.)
---@return string|nil executable path
local function build_local_macho()
  local src = vim.fn.expand '%:p'
  local out_dir = vim.fn.expand '%:p:h' .. '/out'
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

  vim.notify('Built: ' .. exe, vim.log.levels.INFO)
  return exe
end

---Build via Makefile + Docker (Linux ELF64).  Falls back to asking for path.
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
  -- Heuristic: find the binary in out/
  local exe = root .. '/out/base'
  if vim.fn.executable(exe) == 0 then
    return vim.fn.input('Path to executable: ', root .. '/out/', 'file')
  end
  return exe
end

M.configurations = {
  -- ---------------------------------------------------------------
  -- codelldb (local macOS / macho64) — nasm -f macho64 + ld
  -- ---------------------------------------------------------------
  {
    name = 'ASM: Launch (local macho64, lldb)',
    type = 'lldb',
    request = 'launch',
    program = build_local_macho,
    cwd = '${fileDirname}',
    stopOnEntry = true,
    args = {},
  },
  -- ---------------------------------------------------------------
  -- codelldb — attach to existing binary (e.g. Docker-built ELF
  -- debugged remotely, or a binary you built separately)
  -- ---------------------------------------------------------------
  {
    name = 'ASM: Launch (manual path, lldb)',
    type = 'lldb',
    request = 'launch',
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/out/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = true,
    args = {},
  },
  -- ---------------------------------------------------------------
  -- Makefile-driven build (e.g. Docker Linux ELF64) — debugs the
  -- output via lldb.  NOTE: lldb on macOS cannot debug Linux ELF
  -- binaries directly.  This config is useful when the Makefile
  -- produces a Mach-O binary (or when you are running on Linux).
  -- For ELF debugging on macOS use the "GDB (cpptools)" config below.
  -- ---------------------------------------------------------------
  {
    name = 'ASM: Launch (Makefile, lldb)',
    type = 'lldb',
    request = 'launch',
    program = build_via_makefile,
    cwd = '${workspaceFolder}',
    stopOnEntry = true,
    args = {},
  },
}

-- ---------------------------------------------------------------
-- GDB adapter (for Linux ELF debugging, including via Docker)
-- Requires: mason package "cpptools" (Microsoft C++ tools)
-- Install:  :DapInstall cpptools
-- Then point miDebuggerPath at your gdb (or a Docker wrapper).
-- ---------------------------------------------------------------
-- Uncomment and adjust miDebuggerPath when you need GDB debugging:
--
-- M.adapters = {
--   gdb = {
--     type = 'executable',
--     command = vim.fn.stdpath 'data' .. '/mason/packages/cpptools/extension/debugAdapters/bin/OpenDebugAD7',
--     name = 'gdb',
--   },
-- }
--
-- table.insert(M.configurations, {
--   name = 'ASM: Launch (Makefile, GDB)',
--   type = 'gdb',
--   request = 'launch',
--   program = build_via_makefile,
--   cwd = '${workspaceFolder}',
--   stopAtEntry = true,
--   MIMode = 'gdb',
--   miDebuggerPath = '/opt/homebrew/bin/gdb',   -- or a Docker wrapper script
--   setupCommands = {
--     { text = 'set disassembly-flavor intel' },
--   },
-- })

return M
