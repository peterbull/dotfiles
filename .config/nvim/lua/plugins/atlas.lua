return {
  'emrearmagan/atlas.nvim',
  cmd = 'Atlas',
  dependencies = {
    'nvim-tree/nvim-web-devicons',
    'sindrets/diffview.nvim',
  },
  opts = {
    providers = {
      github = {},
    },
    pulls = {
      repo_config = {
        paths = {
          ['calltracking/phonetrac'] = '~/work/ctm',
        },
      },
      diff = {
        open_cmd = 'DiffviewOpen',
      },
    },
  },
  keys = {
    { '<leader>oa', '<cmd>Atlas<cr>', desc = 'Atlas commands' },
    { '<leader>oi', '<cmd>Atlas issues github<cr>', desc = 'GitHub issues' },
    { '<leader>op', '<cmd>Atlas pulls github<cr>', desc = 'GitHub pull requests' },
    { '<leader>od', '<cmd>Atlas browse . discussions<cr>', desc = 'GitHub discussions' },
    { '<leader>os', '<cmd>Atlas search .<cr>', desc = 'Search GitHub' },
    { '<leader>ors', '<cmd>Atlas review<cr>', desc = 'Review pull request' },
    { '<leader>oo', '<cmd>Atlas open .<cr>', desc = 'Open current branch pull request' },
    { '<leader>oR', '<cmd>Atlas browse .<cr>', desc = 'Browse repository' },
  },
}
