return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = function(bufnr)
      -- Skip format-on-save for JS under the ctm repo (~/work/ctm) but not the
      local ctm_root = vim.fs.normalize(vim.fn.expand '~/work/ctm')
      local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
      local in_ctm = vim.startswith(path, ctm_root .. '/') or path == ctm_root
      local is_js = vim.bo[bufnr].filetype == 'javascript' or vim.bo[bufnr].filetype == 'javascriptreact'
      if in_ctm and is_js and not vim.startswith(path, ctm_root .. '/packages/ctm-ui/') then
        return nil
      end
      -- Disable "format_on_save lsp_fallback" for languages that don't
      -- have a well standardized coding style. You can add additional
      -- languages here or re-enable it for the disabled ones.
      local disable_filetypes = { c = true, cpp = true }
      if disable_filetypes[vim.bo[bufnr].filetype] then
        return nil
      else
        return {
          timeout_ms = 500,
          lsp_format = 'fallback',
        }
      end
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      -- Conform can also run multiple formatters sequentially
      python = { 'isort', 'black' },
      --
      -- You can use 'stop_after_first' to run the first available formatter from the list
      javascript = { 'prettierd', 'prettier', stop_after_first = true },
      ruby = { 'rubocop' },
      typescript = { 'prettierd', 'prettier', stop_after_first = true },
      typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
      javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
      html = { 'prettierd', 'prettier', stop_after_first = true },
      json = { 'prettierd', 'prettier', stop_after_first = true },
      rust = { 'rustfmt', lsp_format = 'fallback' },
      zig = { 'zigfmt' },
      sh = { 'shfmt' },
      bash = { 'shfmt' },
      go = { 'gofmt' },
    },
  },
}
