return {
  {
    'linux-cultist/venv-selector.nvim',
    dependencies = {
      'neovim/nvim-lspconfig',
      { 'nvim-telescope/telescope.nvim', branch = '0.1.x', dependencies = { 'nvim-lua/plenary.nvim' } },
    },
    branch = 'regexp', -- v2
    ft = 'python',
    keys = {
      { ',v', '<cmd>VenvSelect<cr>', desc = 'Select Venv' },
    },
    opts = {
      settings = {
        options = {
          notify_user_on_venv_activation = true,
        },
      },
    },
  },
  {
    'Vimjas/vim-python-pep8-indent',
    ft = 'python',
  },
}
