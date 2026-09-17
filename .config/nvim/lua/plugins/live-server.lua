return {
  'barrett-ruth/live-server.nvim',
  -- Load lazily: on first command use or keypress
  cmd = { 'LiveServerStart', 'LiveServerStop', 'LiveServerToggle' },
  keys = {
    { '<leader>ls', '<cmd>LiveServerToggle<CR>', desc = 'Toggle Live Server' },
    { '<leader>lS', '<cmd>LiveServerStart<CR>', desc = 'Start Live Server' },
    { '<leader>lx', '<cmd>LiveServerStop<CR>', desc = 'Stop Live Server' },
  },
  -- vim.g.live_server must be set before the plugin loads (no setup() call)
  init = function()
    vim.g.live_server = {
      port = 5500, -- default port
      browser = true, -- auto-open browser on start
      -- debounce = 120,   -- ms delay before reload after a change
      -- ignore = {},      -- Lua patterns for files to ignore
      -- css_inject = true, -- hot-swap CSS without full reload
    }
  end,
}
