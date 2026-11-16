-- LSP keys for diffview's revision buffers (`diffview://…`, the BEFORE side of a diff and both
-- sides of a commit-to-commit diff). They hold a file's text at a commit, so no language server
-- attaches and K, grd and friends fall back to Vim built-ins (K runs `ri` for Ruby). These keys
-- ask the servers of the same file in the working tree instead. The cursor is carried through a
-- diff of the two texts, so it lands on the same code even when lines moved. Results in the
-- same code stay in the diff pane; others open outside the diff tab, so the layout survives.
local M = {}

---@param buf integer
---@return string|nil
local function working_path(buf)
  local ok, lib = pcall(require, 'diffview.lib')
  if ok then
    for _, view in ipairs(lib.views) do
      if view.files and view.files.iter then
        for _, entry in view.files:iter() do
          for _, symbol in ipairs { 'a', 'b', 'c', 'd' } do
            local pane = entry.layout and entry.layout[symbol]
            if pane and pane.file and pane.file.bufnr == buf then
              return pane.file.absolute_path
            end
          end
        end
      end
    end
  end
  -- File history views keep their files elsewhere; their names are diffview://<repo>/.git/<rev>/<path>.
  local top, rest = vim.api.nvim_buf_get_name(buf):match '^diffview://(.-)/%.git/(.+)$'
  if top then
    return top .. '/' .. rest:gsub('^[^/]+/', '', 1)
  end
end

---@param path string
---@return integer
local function load(path)
  local buf = vim.fn.bufadd(path)
  if not vim.api.nvim_buf_is_loaded(buf) then
    -- The file is often open in another Neovim; skip the swap-file prompt.
    local shortmess = vim.o.shortmess
    vim.opt.shortmess:append 'A'
    local ok, err = pcall(vim.fn.bufload, buf)
    vim.o.shortmess = shortmess
    if not ok then
      error(err, 0)
    end
  end
  return buf
end

---@param buf integer
---@param method string
---@param cb fun()
local function when_attached(buf, method, cb)
  local started = vim.uv.now()
  local told = false
  local function poll()
    if #vim.lsp.get_clients { bufnr = buf, method = method } > 0 then
      cb()
    elseif not told and vim.uv.now() - started > 2000 then
      told = true
      vim.notify('Waiting for the language server to start…', vim.log.levels.INFO)
      vim.defer_fn(poll, 100)
    elseif vim.uv.now() - started > 30000 then
      vim.notify(string.format('No language server for %s on %s', method, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':~:.')), vim.log.levels.WARN)
    else
      vim.defer_fn(poll, 100)
    end
  end
  poll()
end

---@param line string
---@param word string
---@return integer[] 0-based byte columns where `word` stands as a whole word
local function occurrences(line, word)
  local cols = {}
  local pattern = '%f[%w_]' .. vim.pesc(word) .. '%f[^%w_?!]'
  local init = 1
  while true do
    local s = line:find(pattern, init)
    if not s then
      return cols
    end
    table.insert(cols, s - 1)
    init = s + 1
  end
end

--- Carries a position from one text to another: unchanged lines map through the diff, a
--- changed line maps to an identical line nearby, else to the word under the cursor nearby.
---@param from string[]
---@param to string[]
---@param row integer 1-based
---@param col integer 0-based byte column
---@param word string
---@param exact_only? boolean only unchanged or identical lines
---@return integer|nil row, integer|nil col
local function carry(from, to, row, col, word, exact_only)
  local hunks = vim.text.diff(table.concat(from, '\n') .. '\n', table.concat(to, '\n') .. '\n', { result_type = 'indices' }) --[[@as integer[][] ]]
  local offset, estimate = 0, nil
  for _, hunk in ipairs(hunks) do
    local start_a, count_a, start_b, count_b = unpack(hunk)
    if count_a == 0 then
      if start_a >= row then
        break
      end
      offset = offset + count_b
    elseif start_a + count_a - 1 < row then
      offset = offset + count_b - count_a
    elseif start_a > row then
      break
    else
      estimate = math.max(1, count_b > 0 and start_b + math.min(row - start_a, count_b - 1) or start_b)
      break
    end
  end
  if not estimate then
    return row + offset, col
  end

  local text = from[row]
  local best
  if vim.trim(text) ~= '' then
    for i, line in ipairs(to) do
      if line == text and (not best or math.abs(i - estimate) < math.abs(best - estimate)) then
        best = i
      end
    end
  end
  if best then
    return best, col
  end
  if exact_only or word == '' then
    return nil
  end
  for distance = 0, 10 do
    for _, candidate in ipairs { estimate - distance, estimate + distance } do
      local cols = to[candidate] and occurrences(to[candidate], word) or {}
      if #cols > 0 then
        table.sort(cols, function(a, b)
          return math.abs(a - col) < math.abs(b - col)
        end)
        return candidate, cols[1]
      end
    end
  end
  return nil
end

---@class DiffLsp.Target
---@field diff_buf integer
---@field diff_win integer
---@field buf integer working-tree buffer
---@field row integer 1-based, in `buf`
---@field col integer 0-based byte column, in `buf`

---@param method string
---@param cb fun(target: DiffLsp.Target)
local function with_target(method, cb)
  local diff_buf, diff_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local path = working_path(diff_buf)
  if not path then
    vim.notify('Cannot tell which file this diff buffer shows', vim.log.levels.WARN)
    return
  end
  if not vim.uv.fs_stat(path) then
    vim.notify(vim.fn.fnamemodify(path, ':~:.') .. ' is not in the working tree, so no language server can read it', vim.log.levels.WARN)
    return
  end
  local buf = load(path)
  local cursor = vim.api.nvim_win_get_cursor(diff_win)
  local word = vim.fn.expand '<cword>'
  when_attached(buf, method, function()
    local row, col = carry(vim.api.nvim_buf_get_lines(diff_buf, 0, -1, false), vim.api.nvim_buf_get_lines(buf, 0, -1, false), cursor[1], cursor[2], word)
    if not row then
      vim.notify(string.format('`%s` is not near this line in the working-tree file', word), vim.log.levels.WARN)
      return
    end
    cb { diff_buf = diff_buf, diff_win = diff_win, buf = buf, row = row, col = col }
  end)
end

---@param target DiffLsp.Target
---@param method string
---@return fun(client: vim.lsp.Client): table
local function params(target, method)
  return function(client)
    local character = vim.lsp.util.character_offset(target.buf, target.row - 1, target.col, client.offset_encoding)
    local p = { textDocument = { uri = vim.uri_from_bufnr(target.buf) }, position = { line = target.row - 1, character = character } }
    if method == 'textDocument/references' then
      p.context = { includeDeclaration = true }
    end
    return p
  end
end

local function hover()
  local method = 'textDocument/hover'
  with_target(method, function(target)
    vim.lsp.buf_request_all(target.buf, method, params(target, method), function(results)
      local sections = {}
      for client_id, response in pairs(results) do
        if response.err then
          vim.notify('hover: ' .. response.err.message, vim.log.levels.WARN)
        elseif response.result and response.result.contents then
          local lines = vim.lsp.util.convert_input_to_markdown_lines(response.result.contents)
          if vim.trim(table.concat(lines, '\n')) ~= '' then
            table.insert(sections, { name = vim.lsp.get_client_by_id(client_id).name, lines = lines })
          end
        end
      end
      if #sections == 0 then
        vim.notify('No information available', vim.log.levels.INFO)
        return
      end
      if vim.api.nvim_get_current_win() ~= target.diff_win then
        return
      end
      local contents = {}
      for i, section in ipairs(sections) do
        if #sections > 1 then
          if i > 1 then
            table.insert(contents, '---')
          end
          table.insert(contents, '# ' .. section.name)
        end
        vim.list_extend(contents, section.lines)
      end
      vim.lsp.util.open_floating_preview(contents, 'markdown', { focus_id = method })
    end)
  end)
end

--- A window in another tab that can show a file: the last tab used, else any, else a new tab.
local function editing_window()
  local here = vim.api.nvim_get_current_tabpage()
  local tabs = vim.api.nvim_list_tabpages()
  local previous = vim.fn.tabpagenr '#'
  if previous > 0 then
    table.insert(tabs, 1, tabs[previous])
  end
  for _, tab in ipairs(tabs) do
    if tab ~= here then
      local current = vim.api.nvim_tabpage_get_win(tab)
      local wins = { current }
      vim.list_extend(wins, vim.api.nvim_tabpage_list_wins(tab))
      for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == '' and not vim.api.nvim_buf_get_name(buf):match '^diffview://' and vim.api.nvim_win_get_config(win).relative == '' then
          return win
        end
      end
    end
  end
  vim.cmd.tabnew()
  return vim.api.nvim_get_current_win()
end

---@param target DiffLsp.Target
---@param item vim.quickfix.entry
local function open(target, item)
  if vim.api.nvim_win_is_valid(target.diff_win) and vim.fs.normalize(item.filename) == vim.fs.normalize(vim.api.nvim_buf_get_name(target.buf)) then
    local text = vim.api.nvim_buf_get_lines(target.buf, 0, -1, false)
    local row, col = carry(text, vim.api.nvim_buf_get_lines(target.diff_buf, 0, -1, false), item.lnum, item.col - 1, '', true)
    if row then
      vim.api.nvim_set_current_win(target.diff_win)
      vim.cmd "normal! m'"
      vim.api.nvim_win_set_cursor(target.diff_win, { row, col })
      vim.cmd 'normal! zv'
      return
    end
  end
  local win = editing_window()
  vim.api.nvim_set_current_win(win)
  vim.cmd "normal! m'"
  vim.cmd.edit(vim.fn.fnameescape(item.filename))
  vim.api.nvim_win_set_cursor(win, { item.lnum, math.max(item.col - 1, 0) })
  vim.cmd 'normal! zvzz'
end

---@param method string
---@param title string
local function locations(method, title)
  return function()
    with_target(method, function(target)
      vim.lsp.buf_request_all(target.buf, method, params(target, method), function(results)
        local items, seen = {}, {}
        for client_id, response in pairs(results) do
          local client = vim.lsp.get_client_by_id(client_id)
          local result = response.result
          if response.err then
            vim.notify(title .. ': ' .. response.err.message, vim.log.levels.WARN)
          elseif result and client then
            local list = vim.islist(result) and result or { result }
            for _, item in ipairs(vim.lsp.util.locations_to_items(list, client.offset_encoding)) do
              local key = item.filename .. ':' .. item.lnum .. ':' .. item.col
              if not seen[key] then
                seen[key] = true
                table.insert(items, item)
              end
            end
          end
        end
        if #items == 0 then
          vim.notify('No ' .. title:lower() .. ' found', vim.log.levels.INFO)
        elseif #items == 1 then
          open(target, items[1])
        else
          local actions = require 'telescope.actions'
          local conf = require('telescope.config').values
          require('telescope.pickers')
            .new({}, {
              prompt_title = title,
              finder = require('telescope.finders').new_table { results = items, entry_maker = require('telescope.make_entry').gen_from_quickfix {} },
              previewer = conf.qflist_previewer {},
              sorter = conf.generic_sorter {},
              attach_mappings = function(prompt_buf)
                actions.select_default:replace(function()
                  local entry = require('telescope.actions.state').get_selected_entry()
                  actions.close(prompt_buf)
                  if entry then
                    open(target, entry.value)
                  end
                end)
                return true
              end,
            })
            :find()
        end
      end)
    end)
  end
end

local KEYS = {
  { 'K', hover, 'Hover' },
  { 'grd', locations('textDocument/definition', 'Definitions'), '[G]oto [D]efinition' },
  { 'grD', locations('textDocument/declaration', 'Declarations'), '[G]oto [D]eclaration' },
  { 'grt', locations('textDocument/typeDefinition', 'Type definitions'), '[G]oto [T]ype Definition' },
  { 'gri', locations('textDocument/implementation', 'Implementations'), '[G]oto [I]mplementation' },
  { 'grr', locations('textDocument/references', 'References'), '[G]oto [R]eferences' },
}

---@param buf integer
local function attach(buf)
  if vim.b[buf].diff_lsp or vim.bo[buf].filetype == '' or vim.bo[buf].filetype:match '^Diffview' or not working_path(buf) then
    return
  end
  vim.b[buf].diff_lsp = true
  for _, key in ipairs(KEYS) do
    vim.keymap.set('n', key[1], key[2], { buffer = buf, desc = 'LSP (working tree): ' .. key[3] })
  end
end

function M.setup()
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = vim.api.nvim_create_augroup('diff-lsp', { clear = true }),
    pattern = 'diffview://*',
    callback = function(event)
      attach(event.buf)
    end,
  })
end

M._carry = carry

return M
