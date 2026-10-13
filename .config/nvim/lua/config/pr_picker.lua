local M = {}

local function fail(message)
	vim.notify("PR picker: " .. message, vim.log.levels.ERROR)
end

local function run(cwd, argv, callback)
	local ok, err = pcall(vim.system, argv, { cwd = cwd, text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				local detail = vim.trim(result.stderr or "")
				if detail == "" then
					detail = vim.trim(result.stdout or "")
				end
				fail(argv[1] .. " failed (" .. result.code .. "): " .. detail)
				return
			end
			callback(result.stdout or "")
		end)
	end)
	if not ok then
		fail(tostring(err))
	end
end

local function json(cwd, argv, callback)
	run(cwd, argv, function(output)
		local ok, value = pcall(vim.json.decode, output)
		if not ok or type(value) ~= "table" then
			fail("Invalid JSON from " .. argv[1])
			return
		end
		callback(value)
	end)
end

local function open_diff(root, repo, pr)
	json(root, { "gh", "pr", "view", tostring(pr.number), "--repo", repo.url, "--json", "baseRefName" }, function(detail)
		if type(detail.baseRefName) ~= "string" or detail.baseRefName == "" then
			fail("PR base branch is missing")
			return
		end
		local prefix = "refs/pr-picker/" .. pr.number
		run(root, {
			"git", "fetch", "--no-tags", repo.url,
			"+refs/heads/" .. detail.baseRefName .. ":" .. prefix .. "/base",
			"+refs/pull/" .. pr.number .. "/head:" .. prefix .. "/head",
		}, function()
			run(root, { "git", "rev-parse", "--verify", prefix .. "/base^{commit}" }, function(base)
				run(root, { "git", "rev-parse", "--verify", prefix .. "/head^{commit}" }, function(head)
					base, head = vim.trim(base), vim.trim(head)
					if not base:match("^%x+$") or not head:match("^%x+$") then
						fail("Could not resolve fetched PR commits")
						return
					end
					local ok, err = pcall(function()
						require("diffview").open({ "-C=" .. root, base .. "..." .. head })
					end)
					if not ok then
						fail(tostring(err))
					end
				end)
			end)
		end)
	end)
end

local function show_picker(root, repo, prs)
	if #prs == 0 then
		vim.notify("PR picker: No open pull requests in " .. repo.nameWithOwner, vim.log.levels.INFO)
		return
	end
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local sorter = require("telescope.config").values.generic_sorter({})
	-- Keep groups ordered while fuzzy scores rank matches within each group.
	local score = sorter.scoring_function
	sorter.scoring_function = function(self, prompt, line, entry)
		local value = score(self, prompt, line, entry)
		if value < 0 then
			return value
		end
		return entry.value.rank + value / (1 + value)
	end
	require("telescope.pickers").new({}, {
		prompt_title = "Pull requests · " .. repo.nameWithOwner,
		sorting_strategy = "ascending",
		finder = require("telescope.finders").new_table({
			results = prs,
			entry_maker = function(pr)
				local label = string.format("[%s] #%d %s%s · @%s", pr.group, pr.number,
					pr.isDraft and "[draft] " or "", pr.title, pr.author and pr.author.login or "unknown")
				return { value = pr, display = label, ordinal = label }
			end,
		}),
		sorter = sorter,
		previewer = require("telescope.previewers").new_buffer_previewer({
			define_preview = function(self, entry)
				local pr = entry.value
				local lines = { "# " .. pr.title, "", pr.url, "" }
				vim.list_extend(lines, vim.split(pr.body or "", "\n", { plain = true }))
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				vim.bo[self.state.bufnr].filetype = "markdown"
			end,
		}),
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local entry = action_state.get_selected_entry()
				if entry then
					actions.close(prompt_bufnr)
					open_diff(root, repo, entry.value)
				end
			end)
			for _, mode in ipairs({ "i", "n" }) do
				map(mode, "<M-b>", function()
					local entry = action_state.get_selected_entry()
					if entry then
						run(root, { "gh", "pr", "view", tostring(entry.value.number), "--repo", repo.url, "--web" }, function() end)
					end
				end)
				map(mode, "<C-y>", function()
					local entry = action_state.get_selected_entry()
					if entry then
						local ok, err = pcall(vim.fn.setreg, "+", entry.value.url)
						if not ok then
							fail(tostring(err))
						end
					end
				end)
			end
			return true
		end,
	}):find()
end

function M.open()
	local cwd = vim.fn.getcwd()
	run(cwd, { "git", "rev-parse", "--show-toplevel" }, function(output)
		local root = vim.trim(output)
		if root == "" then
			fail("Not in a Git repository")
			return
		end
		json(root, { "gh", "repo", "view", "--json", "nameWithOwner,url" }, function(repo)
			if type(repo.url) ~= "string" or type(repo.nameWithOwner) ~= "string" then
				fail("Could not resolve the GitHub repository")
				return
			end
			local groups = {
				{ name = "Mine", args = { "--author", "@me" } },
				{ name = "Review requested", args = { "--search", "review-requested:@me" } },
				{ name = "Repo", args = {} },
			}
			local prs, seen = {}, {}
			local function load_group(index)
				if index > #groups then
					show_picker(root, repo, prs)
					return
				end
				local group = groups[index]
				local argv = { "gh", "pr", "list", "--repo", repo.url, "--state", "open", "--limit", "50",
					"--json", "number,title,author,isDraft,url,body" }
				vim.list_extend(argv, group.args)
				json(root, argv, function(items)
					for _, pr in ipairs(items) do
						if type(pr.number) ~= "number" or type(pr.title) ~= "string" or type(pr.url) ~= "string" then
							fail("Invalid pull request from gh")
							return
						end
						if not seen[pr.number] then
							seen[pr.number] = true
							pr.group, pr.rank = group.name, index
							prs[#prs + 1] = pr
						end
					end
					load_group(index + 1)
				end)
			end
			load_group(1)
		end)
	end)
end

return M
