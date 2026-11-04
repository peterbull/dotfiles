local jupyter_dir = vim.fn.expand '~/peter-projects/nvim-jupyter'

return {
  {
    dir = jupyter_dir,
    enabled = vim.fn.filereadable(jupyter_dir .. '/lua/jupyter/init.lua') == 1,
    name = 'nvim-jupyter',
    lazy = false,
    -- stylua: ignore
    config = function()
      require('jupyter').setup {
        images = true,
        keymaps = {
          D = 'DeleteCell',
          d = 'Explore',
        },
      }
    end,
  },
}
