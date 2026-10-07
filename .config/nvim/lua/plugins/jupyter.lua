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
        -- Inline pictures over the kitty graphics protocol — ghostty/kitty/
        -- wezterm/konsole only, and off inside tmux (NVIM_JUPYTER_IMAGES=1 to
        -- force). Elsewhere a placeholder line points at the PNG instead.
        images = true,
      }
    end,
  },
}
