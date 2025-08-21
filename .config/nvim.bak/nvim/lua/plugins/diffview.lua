return {
  "sindrets/diffview.nvim",
  lazy = true,
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
    { "<leader>gD", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
    { "<leader>gh", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview File History" },
    { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview Current File History" },
  },
  opts = {
    view = {
      merge_tool = {
        layout = "diff3_mixed",
      },
    },
    keymaps = {
      view = {
        ["q"] = "<cmd>DiffviewClose<cr>",
      },
    },
  },
}
