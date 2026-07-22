return {
	"LintaoAmons/bookmarks.nvim",
	tag = "v4.0.0",
	dependencies = {
		{ "kkharji/sqlite.lua" },
		{ "nvim-telescope/telescope.nvim" },
	},
	config = function()
		require("bookmarks").setup({
			picker = {
				picker_backend = "telescope",
			},
		})

		-- Keymaps (under <leader>m [m]arks group — alongside vim built-in marks)
		vim.keymap.set({ "n", "v" }, "<leader>mm", "<cmd>BookmarksMark<cr>", { desc = "Book[m]ark toggle" })
		vim.keymap.set({ "n", "v" }, "<leader>mo", "<cmd>BookmarksGoto<cr>", { desc = "Bookmark G[o]to" })
		vim.keymap.set({ "n", "v" }, "<leader>ma", "<cmd>BookmarksCommands<cr>", { desc = "Bookmark [A]ctions" })
		vim.keymap.set({ "n", "v" }, "<leader>me", "<cmd>BookmarksDesc<cr>", { desc = "Bookmark D[e]scription" })
		vim.keymap.set("n", "<leader>mt", "<cmd>BookmarksTree<cr>", { desc = "Bookmark [T]ree" })
		vim.keymap.set("n", "<leader>ml", "<cmd>BookmarksLists<cr>", { desc = "Bookmark [L]ists" })
		vim.keymap.set("n", "<leader>mn", "<cmd>BookmarksGotoNext<cr>", { desc = "Bookmark [N]ext" })
		vim.keymap.set("n", "<leader>mp", "<cmd>BookmarksGotoPrev<cr>", { desc = "Bookmark [P]revious" })
		vim.keymap.set("n", "<leader>mg", "<cmd>BookmarksGrep<cr>", { desc = "Bookmark [G]rep" })
		vim.keymap.set("n", "<leader>mi", "<cmd>BookmarksInfo<cr>", { desc = "Bookmark [I]nfo" })
	end,
}
