return {
  'linrongbin16/gitlinker.nvim',
  cmd = 'GitLink',
  opts = {},
  keys = {
    {
      '<leader>gy',
      '<cmd>GitLink<cr>',
      mode = { 'n', 'v' },
      desc = 'Copy git link',
    },
    {
      '<leader>gY',
      '<cmd>GitLink!<cr>',
      mode = { 'n', 'v' },
      desc = 'Open git link in browser',
    },
  },
  dependencies = { 'nvim-lua/plenary.nvim' },
}
