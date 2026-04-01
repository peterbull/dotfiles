-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = { '*.env', '.env*' },
  callback = function()
    -- Disable all diagnostics for this buffer
    vim.diagnostic.enable(false)
  end,
})

vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = { '*/templates/*.yaml', '*/templates/*.tpl', 'Chart.yaml', 'values.yaml' },
  callback = function()
    vim.bo.filetype = 'helm'
  end,
})
-- Stop autocomplete from jumping cursor around when you hit tab after
-- not finishing function params
-- https://github.com/L3MON4D3/LuaSnip/issues/258
vim.api.nvim_create_autocmd('ModeChanged', {
  pattern = '*',
  callback = function()
    if
      ((vim.v.event.old_mode == 's' and vim.v.event.new_mode == 'n') or vim.v.event.old_mode == 'i')
      and require('luasnip').session.current_nodes[vim.api.nvim_get_current_buf()]
      and not require('luasnip').session.jump_active
    then
      require('luasnip').unlink_current()
    end
  end,
})

vim.api.nvim_create_autocmd('ColorScheme', {
  pattern = '*',
  callback = function()
    local groups = {
      '@type',
      '@type.builtin',
      '@lsp.type.class.typescript',
      '@lsp.type.interface.typescript',
      '@lsp.type.type.typescript',
      '@lsp.typemod.class.defaultLibrary.typescript',
      '@lsp.typemod.type.defaultLibrary.typescript',
    }
    for _, group in ipairs(groups) do
      local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
      if ok then
        hl.italic = false
        vim.api.nvim_set_hl(0, group, hl)
      end
    end
  end,
})
