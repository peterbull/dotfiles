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
      -- Notebooks are a projection of .ipynb cell text; a formatter would merge
      -- imports across cell boundaries and rewrite cells you never touched.
      if vim.b[bufnr].nb_buffer then
        return nil
      end
      -- Skip format-on-save for JS under the ctm repos (~/work/ctm, ~/work/ctm-chat):
      -- neither is prettier-formatted. ctm-ui is, so it keeps formatting.
      local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
      local is_js = vim.bo[bufnr].filetype == 'javascript' or vim.bo[bufnr].filetype == 'javascriptreact'
      if is_js then
        for _, dir in ipairs { '~/work/ctm', '~/work/ctm-chat' } do
          local root = vim.fs.normalize(vim.fn.expand(dir))
          local in_root = vim.startswith(path, root .. '/') or path == root
          if in_root and not vim.startswith(path, root .. '/packages/ctm-ui/') then
            return nil
          end
        end
      end
      -- Disable "format_on_save lsp_fallback" for languages that don't
      -- have a well standardized coding style. You can add additional
      -- languages here or re-enable it for the disabled ones.
      local disable_filetypes = { c = true, cpp = true }
      if disable_filetypes[vim.bo[bufnr].filetype] then
        return nil
      else
        return {
          timeout_ms = 1000,
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
