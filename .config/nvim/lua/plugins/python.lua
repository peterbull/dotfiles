return {
  'linux-cultist/venv-selector.nvim',
  dependencies = {
    'neovim/nvim-lspconfig',
    { 'nvim-telescope/telescope.nvim', branch = '0.1.x', dependencies = { 'nvim-lua/plenary.nvim' } },
  },
  ft = 'python',
  keys = {
    { ',v', '<cmd>VenvSelect<cr>', desc = 'Select Venv' },
  },
  opts = {
    search = {
      uv = {
        command = 'uv venv --python-preference only-managed',
      },
    },
    options = {
      auto_refresh = true,
      search_venv_managers = true,
      notify_user_on_venv_activation = true,
    },
  },
}
