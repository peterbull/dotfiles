return {
  {
    dir = '~/peter-projects/nvim-jupyter',
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
