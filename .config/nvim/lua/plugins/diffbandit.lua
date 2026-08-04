-- Drop-in alternative to diffview.nvim. Enabled/disabled by the single
-- toggle in `util.diff_backend`; the `<leader>gv*` entry points mirror the
-- diffview spec so muscle memory carries over.
--
-- The in-view keymaps don't need remapping: diffbandit already ships the
-- same defaults this config relied on in diffview --
--   <Space> toggle stage for the hunk under the cursor
--   q       close the diff / commit panel
--   ]c / [c next / previous hunk
--   C       open / focus the commit panel (file-level staging lives here)

-- diffbandit derives its pane / context / sign-column / status backgrounds
-- from the `Normal` highlight. Our colorscheme runs transparent, so `Normal`
-- has no background and diffbandit falls back to solid black -- painting the
-- whole diff view dark. Strip that background back off so the terminal shows
-- through, matching the rest of the (transparent) editor. Runs after
-- diffbandit's own highlight pass, and on every ColorScheme so it survives
-- dark-notify's light/dark switching.
local function clear_diffbandit_backgrounds()
	-- Groups whose fg carries meaning (a diff color, a separator tint): only
	-- the background is dropped.
	local bg_only = {
		"DiffBanditContext",
		"DiffBanditSignColumn",
		"DiffBanditGap",
		"DiffBanditPlaceholder",
		"DiffBanditEmptyNotice",
		"DiffBanditConnectorContext",
		"DiffBanditConnectorExpansionAdd",
		"DiffBanditConnectorExpansionDelete",
		"DiffBanditConnectorExpansionChange",
		"DiffBanditConnectorExpansionAddUnderline",
	}
	for _, group in ipairs(bg_only) do
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
		if ok then
			hl.bg, hl.ctermbg = nil, nil
			pcall(vim.api.nvim_set_hl, 0, group, hl)
		end
	end

	-- Pane borders / separators: diffbandit's dynamic pass replaces its own
	-- `WinSeparator` link with a blend(Normal.bg, LineNr.fg) color, which looks
	-- wrong on a transparent (black) Normal. Both the normal split group and the
	-- "hidden" split group (used for the separators around the right content
	-- pane and the overview sidecar) get linked to WinSeparator so *every*
	-- separator matches nvim's WinSeparator exactly.
	pcall(vim.api.nvim_set_hl, 0, "DiffBanditSplit", { link = "WinSeparator" })
	pcall(vim.api.nvim_set_hl, 0, "DiffBanditHiddenSplit", { link = "WinSeparator" })

	-- Overview sidecar background: clear both fg and bg so the minimap column
	-- shows the terminal background through instead of a black strip.
	pcall(vim.api.nvim_set_hl, 0, "DiffBanditOverviewContext", { bg = "NONE", fg = "NONE" })

	-- Status line groups: fall back to the editor's real statusline highlights
	-- (which our colorscheme already renders transparent) instead of the
	-- near-black blend diffbandit computed from a black Normal.
	pcall(vim.api.nvim_set_hl, 0, "DiffBanditStatus", { link = "StatusLine" })
	pcall(vim.api.nvim_set_hl, 0, "DiffBanditStatusLine", { link = "StatusLine" })
	pcall(vim.api.nvim_set_hl, 0, "DiffBanditStatusAccent", { link = "StatusLine" })
	pcall(vim.api.nvim_set_hl, 0, "DiffBanditStatusMuted", { link = "StatusLineNC" })
end

return {
	"CoreyKaylor/diffbandit.nvim",
	enabled = require("util.diff_backend") == "diffbandit",
	lazy = true,
	keys = {
		-- DiffviewOpen -> changed-files panel + diff. diffbandit's file list and
		-- file/hunk staging live in the commit panel (diffbandit's analog to
		-- diffview's file panel), so open that rather than the bare `:DiffBanditGit`
		-- diff. Toggle the panel from within a diff with `C`; page files with ]f/[f.
		{ "<leader>gvd", "<cmd>DiffBanditCommitPanel<cr>", desc = "DiffBandit Changes (commit panel)" },
		-- DiffviewFileHistory -> repo-wide commit log browser.
		{ "<leader>gvh", "<cmd>DiffBanditGitLog<cr>", desc = "DiffBandit Git Log" },
		-- DiffviewFileHistory % -> history scoped to the current file.
		{
			"<leader>gvH",
			function()
				local path = vim.fn.expand("%:p")
				if path == "" then
					vim.notify("DiffBandit: no file in the current buffer", vim.log.levels.WARN)
					return
				end
				require("diffbandit").git_log({ pathspecs = { path } })
			end,
			desc = "DiffBandit Current File History",
		},
		-- PR diff (merge-base vs default branch).
		{
			"<leader>gvp",
			function()
				require("util.diffbandit_pr").open()
			end,
			desc = "DiffBandit PR (diff vs default branch)",
		},
	},
	opts = {},
	config = function(_, opts)
		require("diffbandit").setup(opts)

		-- Run once for the current colorscheme, then re-run after every
		-- ColorScheme. diffbandit registers its own ColorScheme handler during
		-- setup() above, so ours -- registered afterwards -- fires after it and
		-- overwrites the black backgrounds it just wrote.
		clear_diffbandit_backgrounds()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("DiffBanditTransparency", { clear = true }),
			callback = clear_diffbandit_backgrounds,
		})

		-- True when the current tab is a diffbandit session/folder (carries the
		-- tabpage var `diffbandit_title`) or a bare commit panel -- gvd opens one
		-- without a session, and it registers in state.panels instead of setting
		-- the title var.
		local function in_diffbandit_tab()
			local tab = vim.api.nvim_get_current_tabpage()
			local ok, title = pcall(vim.api.nvim_tabpage_get_var, tab, "diffbandit_title")
			if ok and title then
				return true
			end
			local state = require("diffbandit.state")
			return state.panels[tab] ~= nil or state.sessions[tab] ~= nil
		end

		-- Backtick toggles the changed-files panel ("file tree"), but ONLY inside
		-- a diffbandit tab. Anywhere else it performs the native jump-to-mark
		-- motion, so this doesn't clobber the global key.
		--
		-- `:DiffBanditCommitPanel` only toggles for the plain working-tree changes
		-- session (queue kind "git"); for the compare/commit *review* sessions
		-- that gvp/gvh open (kind "compare"/"commit") it instead spawns a fresh
		-- panel and tears down the review. So toggle the current tab's session or
		-- panel host directly via diffbandit's state, which works for all three.
		vim.keymap.set("n", "`", function()
			if not in_diffbandit_tab() then
				vim.api.nvim_feedkeys("`", "n", false) -- native jump-to-mark
				return
			end
			local tab = vim.api.nvim_get_current_tabpage()
			local state = require("diffbandit.state")
			local panel = state.panels[tab]
			if panel and not panel.disposed and type(panel.toggle_commit_panel) == "function" then
				panel:toggle_commit_panel()
			elseif state.sessions[tab] and type(state.sessions[tab].toggle_commit_panel) == "function" then
				state.sessions[tab]:toggle_commit_panel()
			else
				vim.cmd("DiffBanditCommitPanel")
			end
		end, { desc = "DiffBandit: toggle file panel (else native `)" })

		-- <C-h>/<C-l> pane navigation. A diffbandit diff is a row of windows
		-- (left content | line-numbers | connector gutter | line-numbers | right
		-- content), so a plain wincmd lands in a gutter. Inside a diffbandit tab,
		-- feed diffbandit's own content-pane jumps (<C-w>h/<C-w>l, mapped
		-- buffer-locally on the content buffers) which skip the gutters;
		-- everywhere else fall back to this config's native split nav (wincmd).
		local function pane_nav(dir)
			local wincmd_key = dir == "left" and "<C-w>h" or "<C-w>l"
			return function()
				if in_diffbandit_tab() then
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(wincmd_key, true, false, true), "m", false)
				else
					vim.cmd("wincmd " .. dir)
				end
			end
		end
		vim.keymap.set("n", "<C-h>", pane_nav("left"), { desc = "Move to left pane (diffbandit-aware)" })
		vim.keymap.set("n", "<C-l>", pane_nav("right"), { desc = "Move to right pane (diffbandit-aware)" })
	end,
}
