local directory = vim.fn.expand '~/peter-projects/codethrasher-inline'
local keys = {}
for _, key in ipairs { '<leader>hd', '<D-k>' } do
  keys[#keys + 1] = {
    key,
    function()
      require('codethrasher-inline').show()
    end,
    mode = 'n',
    desc = 'AI inline edit (file / notebook cell)',
  }
  keys[#keys + 1] = {
    key,
    function()
      require('codethrasher-inline').visual()
    end,
    mode = 'x',
    desc = 'AI inline edit selected lines',
  }
end

return {
  {
    dir = directory,
    enabled = vim.fn.filereadable(directory .. '/lua/codethrasher-inline/init.lua') == 1,
    name = 'codethrasher-inline',
    main = 'codethrasher-inline',
    cmd = { 'CodeThrasherInline', 'CodeThrasherInlineDiscard' },
    opts = {
      pi = {
        executable = vim.fn.stdpath 'config' .. '/bin/pi-mise',
      },
    },
    keys = keys,
  },
}
