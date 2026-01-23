return {
  'folke/trouble.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  opts = {},
  cmd = 'Trouble',
  keys = {
    {
      '<leader>xx',
      function()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        require('trouble').toggle {
          mode = 'diagnostics',
          source = 'diagnostics',
          filter = {
            buf = 0,
            range = {
              start = { line, 0 },
              ['end'] = { line, -1 },
            },
          },
        }
      end,
      desc = 'Current Line Diagnostics (Trouble)',
    },
    {
      '<leader>xX',
      '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
      desc = 'Current Buffer Diagnostics (Trouble)',
    },
    {
      '<leader>XX',
      '<cmd>Trouble diagnostics toggle<cr>',
      desc = 'All Buffers Diagnostics (Trouble)',
    },
    {
      '<leader>cs',
      '<cmd>Trouble symbols toggle focus=false<cr>',
      desc = 'Symbols (Trouble)',
    },
    {
      '<leader>cl',
      '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
      desc = 'LSP Definitions / references / ... (Trouble)',
    },
    {
      '<leader>xL',
      '<cmd>Trouble loclist toggle<cr>',
      desc = 'Location List (Trouble)',
    },
    {
      '<leader>xQ',
      '<cmd>Trouble qflist toggle<cr>',
      desc = 'Quickfix List (Trouble)',
    },
  },
}
