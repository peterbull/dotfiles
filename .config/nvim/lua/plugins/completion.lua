return {
  'saghen/blink.cmp',
  event = 'VimEnter',
  version = '1.*',
  dependencies = {
    {
      'L3MON4D3/LuaSnip',
      version = '2.*',
      build = (function()
        if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
          return
        end
        return 'make install_jsregexp'
      end)(),
      dependencies = {
        {
          'rafamadriz/friendly-snippets',
          config = function()
            require('luasnip.loaders.from_vscode').lazy_load()
          end,
        },
      },
      opts = {},
    },
    'folke/lazydev.nvim',
    { 'saghen/blink.compat', version = '*', lazy = true, opts = {} },
    'rcarriga/cmp-dap',
  },
  --- @module 'blink.cmp'
  --- @type blink.cmp.Config
  opts = function()
    local function is_dap_eval_buffer(bufnr)
      bufnr = bufnr or 0
      local name = vim.api.nvim_buf_get_name(bufnr)
      return name:match '^dap%-eval://' ~= nil
    end

    local function is_dap_completion_buffer()
      return require('cmp_dap').is_dap_buffer() or is_dap_eval_buffer()
    end

    vim.api.nvim_create_autocmd('BufNew', {
      pattern = 'dap-eval://*',
      callback = function(args)
        vim.b[args.buf].completion = true
      end,
    })

    return {
      enabled = function()
        return (vim.bo.buftype ~= 'prompt' and vim.b.completion ~= false) or is_dap_completion_buffer()
      end,
      keymap = {
        preset = 'default',
      },

      appearance = {
        nerd_font_variant = 'mono',
      },

      completion = {
        documentation = { auto_show = false, auto_show_delay_ms = 500 },
        menu = {
          draw = {
            columns = {
              { 'kind_icon' },
              { 'label', 'label_description', gap = 1 },
              { 'kind', 'source_name', gap = 1 },
            },
          },
        },
      },

      sources = {
        default = function()
          local base = { 'lsp', 'path', 'snippets', 'lazydev' }
          if is_dap_eval_buffer() then
            table.insert(base, 1, 'dap')
          end
          return base
        end,

        per_filetype = {
          ['dap-repl'] = { 'dap', 'lsp' },
          ['dapui_watches'] = { 'dap', 'lsp' },
          ['dapui_hover'] = { 'dap' },
        },

        providers = {
          lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
          dap = {
            name = 'dap',
            module = 'blink.compat.source',
            async = true,
            enabled = function()
              return is_dap_completion_buffer()
            end,
          },
        },
      },

      snippets = { preset = 'luasnip' },

      fuzzy = { implementation = 'prefer_rust_with_warning' },

      signature = { enabled = true },
    }
  end,
}
