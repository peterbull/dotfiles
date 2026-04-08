local M = {}

M.configurations = {
  python = {
    {
      name = 'Launch: Current File (root venv)',
      type = 'python',
      request = 'launch',
      program = '${file}',
      pythonPath = function()
        local venv = vim.fn.getcwd() .. '/.venv/bin/python'
        if vim.fn.executable(venv) == 1 then
          return venv
        end
        return 'python3'
      end,
      justMyCode = false,
      showReturnValue = true,
    },
    {
      name = 'Docker: Airflow Worker',
      type = 'python',
      request = 'attach',
      connect = {
        port = 5679,
        host = 'localhost',
      },
      pathMappings = {
        {
          localRoot = function()
            local cwd = vim.fn.getcwd()
            if cwd:lower():find 'airflow' then
              return cwd
            end
            return cwd .. '/airflow'
          end,
          remoteRoot = '/opt/airflow',
        },
      },
      justMyCode = false,
      showReturnValue = true,
    },
  },
}

M.adapters = {
  ---@param cb function
  ---@param config table
  python = function(cb, config)
    if config.request == 'attach' then
      local port = (config.connect or config).port
      local host = (config.connect or config).host or '127.0.0.1'
      print('Connecting to ' .. host .. ':' .. port)
      cb {
        type = 'server',
        port = port,
        host = host,
        options = { source_filetype = 'python' },
      }
    else
      cb {
        type = 'executable',
        command = vim.fn.exepath 'debugpy-adapter',
        options = { source_filetype = 'python' },
      }
    end
  end,
}

return M
