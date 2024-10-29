return {
  "nvimdev/lspsaga.nvim",
  event = "LspAttach",
  config = function()
    -- Sets bulbs to always visible to prevent visual stutter
    vim.opt.signcolumn = "yes:3"
    require("lspsaga").setup({
      lightbulb = { enable = false },
    })
    -- Custom keymaps
    vim.keymap.set("n", "gt", "<cmd>Lspsaga peek_type_definition<CR>", { desc = "Peek type definition" })
  end,
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
}
