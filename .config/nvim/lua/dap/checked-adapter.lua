return function(adapter, files, commands)
  return function(cb)
    local executable = adapter.executable or adapter
    local required = vim.list_extend({ executable.command }, commands or {})
    for _, command in ipairs(required) do
      if vim.fn.executable(command) ~= 1 then
        vim.notify('Missing debug executable: ' .. command .. ' (provision its Mason package or toolchain)', vim.log.levels.ERROR)
        return
      end
    end
    for _, file in ipairs(files or {}) do
      if vim.fn.filereadable(file) ~= 1 then
        vim.notify('Missing debug adapter script: ' .. file .. ' (provision its Mason package)', vim.log.levels.ERROR)
        return
      end
    end
    cb(adapter)
  end
end
