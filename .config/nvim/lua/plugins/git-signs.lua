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
      '<leader>gR',
      function()
        require('config.git_gutter').toggle_pr()
      end,
      desc = 'Toggle PR changes in gutter (current file)',
    },
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
        if vim.b.gitsigns_pr_base then
          vim.notify('Switch to local edits with <leader>gR before resetting a hunk', vim.log.levels.WARN)
          return
        end
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
