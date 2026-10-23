local branch_diff_pending = false

local function get_default_branch()
	local out = vim.fn.system({ "git", "symbolic-ref", "refs/remotes/origin/HEAD" })
	local db = out:match("refs/remotes/origin/([^%s]+)")
	if db then
		return db
	end

	local function ref_exists(ref)
		vim.fn.system({ "git", "show-ref", "--verify", "--quiet", ref })
		return vim.v.shell_error == 0
	end
	for _, prefix in ipairs({ "refs/remotes/origin/", "refs/heads/" }) do
		for _, branch in ipairs({ "master", "main" }) do
			if ref_exists(prefix .. branch) then
				return branch
			end
		end
	end
	return "master"
end

-- Undo the intent-to-add entries the branch-diff keymaps (<leader>gm / <leader>gM) create. Only
-- reset entries that still point at the empty blob, so a file the user
-- actually staged inside the diff view keeps its staged content.
local function cleanup_iadd()
	local pending = vim.g.diffview_iadd
	if not pending or #pending.files == 0 then
		return
	end
	vim.g.diffview_iadd = nil

	local out = vim.fn.system(
		vim.list_extend(
			{ "git", "-C", pending.toplevel, "-c", "core.quotePath=false", "ls-files", "--stage", "--" },
			pending.files
		)
	)
	local still = {}
	for _, line in ipairs(vim.split(out, "\n", { plain = true })) do
		local hash, path = line:match("^%d+%s+(%x+)%s+%d\t(.*)$")
		if hash == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391" then
			still[#still + 1] = path
		end
	end
	if #still > 0 then
		vim.fn.system(vim.list_extend({ "git", "-C", pending.toplevel, "reset", "-q", "--" }, still))
	end
end

-- diffview only lists untracked files for index-vs-worktree diffs, so mark
-- untracked (non-ignored) files intent-to-add and open a working-tree diff
-- against `base_rev`; untracked files then show up as new files. cleanup_iadd()
-- undoes the index changes when the view closes (or on quit).
local function open_branch_diff(base_rev)
	local toplevel = vim.fn.system({ "git", "rev-parse", "--show-toplevel" }):gsub("%s", "")
	if toplevel == "" or vim.v.shell_error ~= 0 then
		vim.notify("Not in a git repo", vim.log.levels.ERROR)
		return
	end
	local untracked = vim.fn.system({
		"git",
		"-C",
		toplevel,
		"-c",
		"core.quotePath=false",
		"ls-files",
		"--others",
		"--exclude-standard",
	})
	local files = {}
	for _, f in ipairs(vim.split(untracked, "\n", { plain = true })) do
		if f ~= "" then
			files[#files + 1] = f
		end
	end
	if #files > 0 then
		vim.fn.system(vim.list_extend({ "git", "-C", toplevel, "add", "-N", "--" }, files))
	end
	vim.g.diffview_iadd = { toplevel = toplevel, files = files }
	vim.cmd("DiffviewOpen --untracked-files=all " .. base_rev)
end

return {
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
		keys = {
			{
				"<leader>gvp",
				function()
					require("config.pr_picker").open()
				end,
				desc = "[G]it [v]iew [p]ull requests",
			},
			{
				"<leader>gM",
				function()
					local lib = require("diffview.lib")
					if next(lib.views) ~= nil then
						vim.cmd("DiffviewClose")
						return
					end
					vim.cmd("DiffviewOpen --untracked-files=all")
				end,
				desc = "Diff my worktree vs last commit (HEAD), incl. untracked",
			},
			{
				"<leader>gm",
				function()
					local lib = require("diffview.lib")
					if next(lib.views) ~= nil then
						vim.cmd("DiffviewClose")
						return
					end

					if branch_diff_pending then
						vim.notify("Fetching origin for branch diff", vim.log.levels.INFO)
						return
					end

					local cwd = vim.fn.getcwd()
					local tab = vim.api.nvim_get_current_tabpage()
					local default_branch = get_default_branch()
					local remote_ref = "refs/remotes/origin/" .. default_branch
					branch_diff_pending = true

					local complete = vim.schedule_wrap(function(result)
						branch_diff_pending = false
						if result.code ~= 0 then
							local reason = (result.stderr or ""):gsub("%s+$", "")
							vim.notify(
								"Could not fetch origin/" .. default_branch .. "; trying cached ref. " .. reason,
								vim.log.levels.WARN
							)
						end
						if
							vim.fn.getcwd() ~= cwd
							or vim.api.nvim_get_current_tabpage() ~= tab
							or next(lib.views) ~= nil
						then
							return
						end
						local merge_base = vim.fn.system({ "git", "-C", cwd, "merge-base", "HEAD", remote_ref })
						if vim.v.shell_error ~= 0 or merge_base:match("^%s*$") then
							vim.notify(
								"Could not find merge base with origin/"
									.. default_branch
									.. ": "
									.. merge_base:gsub("%s+$", ""),
								vim.log.levels.ERROR
							)
							return
						end
						open_branch_diff(merge_base:gsub("%s", ""))
					end)
					local ok, result = pcall(vim.system, {
						"git",
						"fetch",
						"--no-tags",
						"--no-recurse-submodules",
						"origin",
						"+refs/heads/" .. default_branch .. ":" .. remote_ref,
					}, { cwd = cwd, text = true, timeout = 15000 }, complete)
					if not ok then
						complete({ code = -1, stderr = tostring(result) })
					end
				end,
				desc = "Fetch origin and diff vs default branch point, incl. untracked",
			},
			{
				"<leader>gd",
				function()
					local lib = require("diffview.lib")
					if next(lib.views) == nil then
						vim.cmd("DiffviewOpen")
					else
						vim.cmd("DiffviewClose")
					end
				end,
				desc = "Current file changes (staged/unstaged)",
			},
			{
				"<leader>gf",
				function()
					local lib = require("diffview.lib")
					if next(lib.views) == nil then
						vim.g.diffview_pinned_file = vim.fn.expand("%:p")
						vim.cmd("DiffviewFileHistory %")
					else
						vim.cmd("DiffviewClose")
					end
				end,
				desc = "[G]it [f]ile History",
			},
			{
				"<leader>gh",
				function()
					local lib = require("diffview.lib")
					if next(lib.views) == nil then
						vim.cmd("DiffviewFileHistory")
					else
						vim.cmd("DiffviewClose")
					end
				end,
				desc = "[G]it [H]istory",
			},

			{
				"<leader>gT",
				function()
					local lib = require("diffview.lib")
					if next(lib.views) ~= nil then
						vim.cmd("DiffviewClose")
						return
					end

					vim.ui.input({ prompt = "Base tag: " }, function(tag1)
						if not tag1 or tag1 == "" then
							return
						end
						vim.ui.input({ prompt = "Compare tag: " }, function(tag2)
							if not tag2 or tag2 == "" then
								return
							end
							vim.cmd("DiffviewOpen " .. tag1 .. ".." .. tag2)
						end)
					end)
				end,
				desc = "[G]it diff between two [T]ags (any revs: tags, shas, branches)",
			},
			{
				"<leader>gC",
				function()
					local lib = require("diffview.lib")
					if next(lib.views) ~= nil then
						vim.cmd("DiffviewClose")
						return
					end

					vim.ui.input({ prompt = "Commit rev: ", default = "HEAD" }, function(rev)
						if not rev or rev == "" then
							return
						end
						-- '<rev>^!' == '<rev>^..<rev>': only what that commit introduced, i.e.
						-- GitHub's commit view. A range or modifier typed as-is is passed through.
						local spec = (rev:find("..", 1, true) or rev:match("[%!^]$")) and rev or rev .. "^!"
						vim.cmd("DiffviewOpen " .. spec)
					end)
				end,
				desc = "[G]it [C]ommit changes (what one commit did, like GitHub)",
			},
			{
				"<leader>gA",
				function()
					local lib = require("diffview.lib")
					local current_branch = vim.fn.system({ "git", "branch", "--show-current" }):gsub("%s", "")
					local default_branch = get_default_branch()
					local cmd = current_branch == default_branch and "DiffviewOpen"
						or ("DiffviewOpen " .. default_branch)

					if next(lib.views) == nil then
						vim.cmd(cmd)
					else
						vim.cmd("DiffviewClose")
					end
				end,
				desc = "[G]it [A]ll changes vs default branch",
			},
		},
		config = function()
			require("diffview").setup({
				use_icons = vim.g.have_nerd_font,
				view = {
					default = {
						layout = "diff2_horizontal",
					},
				},
				keymaps = {
					file_history_panel = {
						{
							"n",
							"gd",
							function()
								local lib = require("diffview.lib")
								local view = lib.get_current_view()
								if not view then
									return
								end

								-- try different ways to get the entry under cursor
								local entry = view.panel:get_item_at_cursor()
								if not entry then
									vim.notify("no entry under cursor", vim.log.levels.ERROR)
									return
								end
								local hash = entry.commit and entry.commit.hash or entry.hash

								local file = vim.g.diffview_pinned_file
								if not file or file == "" then
									vim.notify(
										"No pinned file — open history with <leader>gf first",
										vim.log.levels.WARN
									)
									return
								end

								vim.notify(
									"hash: " .. hash .. "\nfile: " .. file,
									vim.log.levels.INFO,
									{ timeout = 5000 }
								)

								vim.cmd("DiffviewClose")
								vim.schedule(function()
									vim.cmd(
										"DiffviewOpen " .. hash .. ".. --imply-local -- " .. vim.fn.fnameescape(file)
									)
								end)
							end,
							{ desc = "Diff working tree vs commit under cursor" },
						},
					},
				},
			})

			-- Undo intent-to-add entries (see <leader>gM) when the diff view closes
			-- or on quit, so the index is left exactly as we found it.
			vim.api.nvim_create_autocmd("User", {
				pattern = "DiffviewViewClosed",
				callback = cleanup_iadd,
			})
			vim.api.nvim_create_autocmd("VimLeavePre", {
				callback = cleanup_iadd,
			})
		end,
	},
	{
		"NeogitOrg/neogit",
		dependencies = {
			"sindrets/diffview.nvim",
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope.nvim",
			{ "nvim-tree/nvim-web-devicons", enabled = vim.g.have_nerd_font },
		},
		cmd = "Neogit",
		keys = {
			{
				"<leader>gg",
				function()
					require("neogit").open()
				end,
				desc = "[g]it [g]it (Neogit status)",
			},
			{
				"<leader>gc",
				function()
					require("neogit").open({ "commit" })
				end,
				desc = "[g]it [c]ommit",
			},
			{
				"<leader>gp",
				function()
					require("neogit").open({ "push" })
				end,
				desc = "[g]it [p]ush",
			},
			{
				"<leader>gP",
				function()
					require("neogit").open({ "pull" })
				end,
				desc = "[g]it [p]ull",
			},
			{
				"<leader>gl",
				function()
					require("neogit").open({ "log" })
				end,
				desc = "[g]it [l]og",
			},
			{
				"<leader>gB",
				function()
					require("neogit").open({ "branch" })
				end,
				desc = "[g]it [B]ranch",
			},
			{
				"<leader>gs",
				function()
					require("neogit").open({ "stash" })
				end,
				desc = "[g]it [s]tash",
			},
		},
		opts = {
			integrations = {
				diffview = true,
				telescope = true,
			},
		},
	},
}
