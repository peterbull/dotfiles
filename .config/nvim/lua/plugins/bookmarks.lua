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
		vim.keymap.set({ "n", "v" }, "<leader>ma", "<cmd>BookmarksCommands<cr>", { desc = "Bookmark [A]ctions" })
		vim.keymap.set({ "n", "v" }, "<leader>me", "<cmd>BookmarksDesc<cr>", { desc = "Bookmark D[e]scription" })
		vim.keymap.set("n", "<leader>mt", "<cmd>BookmarksTree<cr>", { desc = "Bookmark [T]ree" })
		vim.keymap.set("n", "<leader>ml", "<cmd>BookmarksLists<cr>", { desc = "Bookmark [L]ists" })
		require("config.bookmark_walk").setup()
		vim.keymap.set("n", "<leader>mg", "<cmd>BookmarksGrep<cr>", { desc = "Bookmark [G]rep" })
		vim.keymap.set("n", "<leader>mi", "<cmd>BookmarksInfo<cr>", { desc = "Bookmark [I]nfo" })

		-- Browse all bookmark groups/lists in a Telescope picker and delete the selected ones
		-- (<Tab> marks several; <CR> deletes the marked groups, or the one under the cursor).
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
				prompt_title = "Bookmark Groups (delete · <Tab> to multi-select)",
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
						local nodes = {}
						for _, entry in ipairs(action_state.get_current_picker(bufnr):get_multi_selection()) do
							nodes[#nodes + 1] = entry.value
						end
						if #nodes == 0 then
							local selection = action_state.get_selected_entry()
							if selection then
								nodes[1] = selection.value
							end
						end
						actions.close(bufnr)
						if #nodes == 0 then
							return
						end
						local prompt = #nodes == 1
								and string.format('Delete group "%s" and all its bookmarks?', nodes[1].name)
							or string.format("Delete %d groups and all their bookmarks?", #nodes)
						vim.ui.select({ "Delete", "Cancel" }, { prompt = prompt }, function(choice)
							if choice ~= "Delete" then
								return
							end
							local failed = {}
							for _, node in ipairs(nodes) do
								local ok, err = pcall(Service.delete_node, node.id)
								if not ok then
									failed[#failed + 1] = string.format("%s (%s)", node.name, err)
								end
							end
							Sign.safe_refresh_signs()
							if #failed > 0 then
								vim.notify("Could not delete: " .. table.concat(failed, ", "), vim.log.levels.ERROR)
							end
							vim.notify(
								string.format("Deleted %d bookmark group(s)", #nodes - #failed),
								vim.log.levels.INFO
							)
						end)
					end)
					return true
				end,
			})
			picker:find()
		end, { desc = "Bookmark [D]elete groups (picker)" })
	end,
}
