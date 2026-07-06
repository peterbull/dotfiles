-- plugins/treesitter.lua
-- Migrated to nvim-treesitter `main` branch API (required for Neovim 0.12 compat).
-- The `main` branch is a rewrite: it is now a parser/query installer only.
-- Highlighting, indentation, and per-buffer activation are handled manually
-- via Neovim's native `vim.treesitter` APIs instead of a `setup({...})` config table.

return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false,
	build = ":TSUpdate",

	keys = {
		{
			"<leader>ti",
			function()
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					local buf = vim.api.nvim_win_get_buf(win)
					local ft = vim.bo[buf].filetype
					if ft == "query" then
						vim.api.nvim_win_close(win, true)
						return
					end
				end
				vim.cmd("InspectTree")
			end,
			desc = "Toggle Treesitter [I]nspect",
		},
	},

	config = function()
		-- Register the custom `reef` parser (out-of-tree grammar).
		-- NOTE: registration shape on `main` differs from `master`'s
		-- `nvim-treesitter.parsers.get_parser_configs()` API. Verify this against
		-- the current README (`:help nvim-treesitter-main`) if TSInstall reef fails,
		-- as this API has iterated since initial `main` release.
		require("nvim-treesitter.parsers").reef = {
			install_info = {
				url = vim.fn.expand("~/peter-projects/tree-sitter-reef"),
				files = { "src/parser.c" },
				branch = "main",
			},
		}
		vim.filetype.add({ extension = { reef = "reef" } })

		-- Parsers to install (replaces old `ensure_installed`).
		local parsers = {
			"bash",
			"c",
			"cpp",
			"diff",
			"html",
			"lua",
			"luadoc",
			"markdown",
			"markdown_inline",
			"query",
			"vim",
			"vimdoc",
			"javascript",
			"typescript",
			"json",
			"zig",
			"rust",
			"python",
			"ruby",
			"reef",
		}

		require("nvim-treesitter").install(parsers)

		-- Filetypes to exclude from treesitter indentexpr (ported from old
		-- `indent = { disable = { "ruby" } }`).
		local indent_disabled = {
			ruby = true,
		}

		-- Activate highlighting (+ indent where not excluded) per-buffer.
		-- Replaces old `highlight = { enable = true }` / `indent = { enable = true }`.
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "*",
			callback = function(args)
				local buf = args.buf
				local ft = vim.bo[buf].filetype

				local ok = pcall(vim.treesitter.start, buf)
				if not ok then
					return
				end

				if not indent_disabled[ft] then
					vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end,
		})
	end,
}
