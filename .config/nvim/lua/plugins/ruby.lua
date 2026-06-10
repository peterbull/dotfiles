-- return {}
return {
  {
    'adam12/ruby-lsp.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'neovim/nvim-lspconfig',
    },
    ft = { 'ruby', 'eruby' },
    keys = {

      {
        'grl',
        function()
          vim.lsp.codelens.run()
        end,
        desc = 'Run Code Lens',
      },
    },
    config = true,
    opts = {
      lspconfig = {
        on_attach = function(client, bufnr)
          -- Explicitly bind K to hover for ruby buffers
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, {
            buffer = bufnr,
            desc = 'LSP Hover',
          })
        end,
        init_options = {},
      },
    },
  },
}
