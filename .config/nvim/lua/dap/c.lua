local M = {}
M.adapters = {}
M.configurations = {
  {
    name = 'Launch C Default',
    type = 'lldb',
    request = 'launch',
    program = function()
      local extension = vim.fn.expand '%:e'

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

      if extension == 'c' then
        -- search from the current file's directory, not cwd
        local file_dir = vim.fn.expand '%:p:h'
        local root = find_root('Makefile', file_dir)
        if not root then
          vim.notify('No Makefile found', vim.log.levels.ERROR)
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/build/', 'file')
        end
        vim.notify('Building in: ' .. root, vim.log.levels.INFO)
        local result = vim.fn.system('make -C ' .. root)
        if vim.v.shell_error ~= 0 then
          vim.notify('Build failed: ' .. result, vim.log.levels.ERROR)
          return vim.fn.input('Path to executable: ', root .. '/build/', 'file')
        end
        return root .. '/build/main'
      end

      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = {},
  },
}

return M
