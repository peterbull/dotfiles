return {
  'lewis6991/gitsigns.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  opts = {
    signcolumn = true,
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '-' },
      topdelete = { text = '-' },
      changedelete = { text = '~' },
      untracked = { text = '+' },
    },
    signs_staged = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '-' },
      topdelete = { text = '-' },
      changedelete = { text = '~' },
    },
  },

  keys = {
    {
      '<leader>gt',
      function()
        local enabled = require('gitsigns').toggle_signs()
        vim.notify('Git gutter signs: ' .. (enabled and 'on' or 'off'))
      end,
      desc = '[T]oggle Git gutter signs',
    },
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
