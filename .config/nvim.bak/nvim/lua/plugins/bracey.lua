return {
  "turbio/bracey.vim",
  build = "npm install --prefix server",
  cmd = { "Bracey", "BraceyStop", "BraceyReload" },
  config = function()
    vim.g.bracey_auto_start_server = 1
    vim.g.bracey_server_allow_remote_connections = 0
    vim.g.bracey_server_port = 3000
  end,
}
