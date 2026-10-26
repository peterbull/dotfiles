return {
  'mrcjkb/rustaceanvim',
  version = '^9',
  lazy = false,
  init = function()
    vim.g.rustaceanvim = {
      dap = {
        load_rust_types = true,
      },
    }
  end,
}
