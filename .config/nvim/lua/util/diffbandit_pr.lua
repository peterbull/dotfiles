-- "Pull request" diff for diffbandit.nvim: what this branch would show as a
-- PR against its default branch (main/master), i.e. the diff from the
-- merge-base, not a plain two-dot diff against the branch tip.
--
-- Mirror of util.diffview_pr. diffbandit's `git_compare` does a merge-base
-- comparison by default (pass `direct = true` to get a two-dot diff), so
-- `git_compare(target, "HEAD")` matches diffview's `target...HEAD`.
local M = {}

local function ref_exists(ref)
	vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", ref })
	return vim.v.shell_error == 0
end

local function default_branch()
	local out = vim.fn.systemlist({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
	if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
		return out[1]
	end

	for _, ref in ipairs({ "origin/main", "origin/master", "main", "master" }) do
		if ref_exists(ref) then
			return ref
		end
	end
end

function M.open()
	local target = default_branch()
	if not target then
		vim.notify("DiffBandit PR: couldn't find a main/master branch to diff against", vim.log.levels.ERROR)
		return
	end

	local session, err = require("diffbandit").git_compare(target, "HEAD")
	if not session and err then
		vim.notify("DiffBandit PR: " .. tostring(err), vim.log.levels.ERROR)
	end
end

return M
