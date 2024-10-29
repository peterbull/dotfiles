return {
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    build = ":UpdateRemotePlugins",
    init = function()
      vim.g.molten_output_win_max_height = 12
      -- Recommended keybindings
      local map = vim.keymap.set
      local opts = { silent = true }
      map("n", "<leader>mi", ":MoltenInit<CR>", { silent = true, desc = "Initialize Molten" })
      map("n", "<leader>me", ":MoltenEvaluateOperator<CR>", { silent = true, desc = "Run operator selection" })
      map("n", "<leader>ml", ":MoltenEvaluateLine<CR>", { silent = true, desc = "Evaluate line" })
      map("n", "<leader>mr", ":MoltenReevaluateCell<CR>", { silent = true, desc = "Re-evaluate cell" })
      map("v", "<leader>ms", ":<C-u>MoltenEvaluateVisual<CR>gv", { silent = true, desc = "Evaluate visual selection" })
      -- Output management
      map("n", "<leader>md", ":MoltenDelete<CR>", { silent = true, desc = "Delete cell" })
      map("n", "<leader>mh", ":MoltenHideOutput<CR>", { silent = true, desc = "Hide output" })
      map("n", "<leader>mo", ":noautocmd MoltenEnterOutput<CR>", { silent = true, desc = "Show/enter output" })
    end,
  },
}
