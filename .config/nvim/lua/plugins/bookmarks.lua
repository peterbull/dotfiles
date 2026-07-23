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

		-- Browse all bookmark groups/lists in a Telescope picker and delete the selected one.
		-- (The plugin has no built-in group browser, so we build one on top of
		--  Repo.find_lists() + Service.delete_node(), which cascade-deletes children.)
		vim.keymap.set("n", "<leader>md", function()
			local ok, telescope = pcall(require, "telescope.pickers")
			if not ok then
				vim.notify("telescope.nvim is required for group browsing", vim.log.levels.ERROR)
				return
			end
			local finders = require("telescope.finders")
			local conf = require("telescope.config").values
			local actions = require("telescope.actions")
			local action_state = require("telescope.actions.state")
			local Repo = require("bookmarks.domain.repo")
			local Service = require("bookmarks.domain.service")
			local Sign = require("bookmarks.sign")

			local lists = Repo.find_lists()
			if #lists == 0 then
				vim.notify("No bookmark groups found", vim.log.levels.INFO)
				return
			end

			local picker = telescope.new({}, {
				prompt_title = "Bookmark Groups (delete)",
				sorter = conf.generic_sorter({}),
				finder = finders.new_table({
					results = lists,
					entry_maker = function(node)
						return {
							value = node,
							display = node.name,
							ordinal = node.name,
						}
					end,
				}),
				attach_mappings = function(bufnr, map)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(bufnr)
						if not selection then
							return
						end
						local node = selection.value
						vim.ui.select({ "Delete", "Cancel" }, {
							prompt = string.format('Delete group "%s" and all its bookmarks?', node.name),
						}, function(choice)
							if choice == "Delete" then
								pcall(Service.delete_node, node.id)
								Sign.safe_refresh_signs()
								vim.notify(string.format('Deleted bookmark group "%s"', node.name), vim.log.levels.INFO)
							end
						end)
					end)
					return true
				end,
			})
			picker:find()
		end, { desc = "Bookmark [D]elete group (picker)" })
	end,
}
