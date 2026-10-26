if vim.fn.has 'nvim-0.12' == 0 then
  error 'This config requires Neovim 0.12 or later. Run: bob use 0.12.6'
end

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local plugin_root = vim.fn.stdpath 'data' .. '/lazy-0.12'

---@diagnostic disable-next-line: undefined-global
if init_debug then
  local osvpath = plugin_root .. '/one-small-step-for-vimkind'
  vim.opt.rtp:prepend(osvpath)
  require('osv').launch { port = 8086, blocking = true }
end

vim.g.have_nerd_font = true

require 'config.options'
require 'config.keymaps'
require 'config.autocmds'

local lazypath = plugin_root .. '/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end

local rtp = vim.opt.rtp
rtp:prepend(lazypath)

vim.lsp.log.set_level 'warn'

require('lazy').setup({
  { import = 'plugins' },
}, {
  root = plugin_root,
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

vim.lsp.inlay_hint.enable(false)
