local M = {}
local tools = vim.fn.stdpath 'config' .. '/tools/rbs/'

local function command(mode, root)
  return { 'mise', 'exec', '--', 'bundle', 'exec', '--gemfile', tools .. 'Gemfile', 'ruby', tools .. 'server.rb', mode, root }
end

local function project(buf)
  if vim.bo[buf].filetype ~= 'ruby' then
    return
  end
  local root = vim.fs.root(buf, { 'Gemfile', '.git' })
  if not root or not vim.uv.fs_stat(root .. '/.ruby-lsp/Steepfile') then
    return
  end
  local header = vim.api.nvim_buf_get_lines(buf, 0, 5, false)
  if table.concat(header, '\n'):find('# rbs_inline: enabled', 1, true) then
    return root
  end
end

local function hover()
  local line = vim.api.nvim_get_current_line()
  local name, dtype = line:match '^%s*attr_%w+%s+:([%w_]+)%s*#:%s*(.+)$'
  if not name then
    name, dtype = line:match '^%s*:([%w_]+),?%s*#:%s*(.+)$'
  end
  -- The LSP sees declaration arguments as Symbols; show their explicit RBS annotation.
  if name then
    return vim.lsp.util.open_floating_preview({ name .. ': ' .. dtype }, 'rbs', { border = 'rounded' })
  end
  return vim.lsp.buf.hover { border = 'rounded' }
end

function M.attach(buf)
  local root = project(buf)
  if not root then
    return
  end
  return vim.lsp.start({
    name = 'steep',
    cmd = command('langserver', root),
    cmd_cwd = root,
    root_dir = root,
    capabilities = require('blink.cmp').get_lsp_capabilities(),
    on_attach = function(_, attached)
      vim.keymap.set('n', 'K', hover, { buffer = attached, desc = 'RBS types and LSP hover' })
    end,
  }, { bufnr = buf })
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ruby-inline-rbs', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'ruby',
    callback = function(event)
      M.attach(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = '*.rb',
    callback = function(event)
      local root = project(event.buf)
      if not root then
        return
      end
      M.attach(event.buf)
      vim.system(
        command('generate', root),
        { cwd = root, text = true },
        vim.schedule_wrap(function(result)
          if result.code ~= 0 then
            vim.notify('RBS generation failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
            return
          end
          local changes = vim.tbl_map(function(path)
            return { uri = vim.uri_from_fname(path), type = 2 }
          end, vim.fn.glob(root .. '/.ruby-lsp/rbs/generated/**/*.rbs', false, true))
          for _, client in ipairs(vim.lsp.get_clients { name = 'steep' }) do
            if client.config.root_dir == root then
              client:notify('workspace/didChangeWatchedFiles', { changes = changes })
            end
          end
        end)
      )
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.attach(buf)
    end
  end
end

return M
