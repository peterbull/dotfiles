return {
  'lewis6991/gitsigns.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  opts = {
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
  },

  keys = {
    {
      '<leader>grh',
      function()
        require('gitsigns').reset_hunk()
      end,
      desc = 'Reset Hunk',
    },
    {
      '<leader>gb',
      function()
        local gitsigns = require 'gitsigns'
        gitsigns.blame()
      end,
      desc = '[B]lame for Current Buffer',
    },
  },
}
