return {
  'saghen/blink.cmp',
  event = 'VimEnter',
  version = '1.*',
  dependencies = {
    -- Snippet Engine
    {
      'L3MON4D3/LuaSnip',
      version = '2.*',
      build = (function()
        -- Build Step is needed for regex support in snippets.
        -- This step is not supported in many windows environments.
        -- Remove the below condition to re-enable on windows.
        if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
          return
        end
        return 'make install_jsregexp'
      end)(),
      dependencies = {
        -- `friendly-snippets` contains a variety of premade snippets.
        --    See the README about individual language/framework/plugin snippets:
        --    https://github.com/rafamadriz/friendly-snippets
        {
          'rafamadriz/friendly-snippets',
          config = function()
            require('luasnip.loaders.from_vscode').lazy_load()
          end,
        },
      },
      opts = {
        menu = {
          draw = {
            columns = {
              { 'kind_icon', 'label', gap = 1 },
              { 'kind' },
            },
            components = {
              kind_icon = {
                text = function(item)
                  local kind = require('lspkind').symbol_map[item.kind] or ''
                  return kind .. ' '
                end,
                highlight = 'CmpItemKind',
              },
              label = {
                text = function(item)
                  return item.label
                end,
                highlight = 'CmpItemAbbr',
              },
              kind = {
                text = function(item)
                  return item.kind
                end,
                highlight = 'CmpItemKind',
              },
            },
          },
        },
      },
    },
    'folke/lazydev.nvim',
    -- DAP completion dependencies
    { 'saghen/blink.compat', version = '*', lazy = true, opts = {} },
    'rcarriga/cmp-dap',
  },
  --- @module 'blink.cmp'
  --- @type blink.cmp.Config
  opts = function()
    -- Helper: detect dap-eval:// buffers (used for multi-line DAP eval)
    -- These get the target language's filetype, not a dedicated dap filetype,
    -- so we must detect them by buffer name instead.
    local function is_dap_eval_buffer(bufnr)
      bufnr = bufnr or 0
      local name = vim.api.nvim_buf_get_name(bufnr)
      return name:match '^dap%-eval://' ~= nil
    end

    local function is_dap_completion_buffer()
      return require('cmp_dap').is_dap_buffer() or is_dap_eval_buffer()
    end

    -- Ensure dap-eval buffers get completion enabled, similar to the
    -- FileType autocmd used for dap-repl/dapui_watches/dapui_hover
    vim.api.nvim_create_autocmd('BufNew', {
      pattern = 'dap-eval://*',
      callback = function(args)
        vim.b[args.buf].completion = true
      end,
    })

    return {
      -- Allow blink to activate inside the DAP prompt buffer and dap-eval buffers
      enabled = function()
        return (vim.bo.buftype ~= 'prompt' and vim.b.completion ~= false) or is_dap_completion_buffer()
      end,
      keymap = {
        -- 'default' (recommended) for mappings similar to built-in completions
        --   <c-y> to accept ([y]es) the completion.
        --    This will auto-import if your LSP supports it.
        --    This will expand snippets if the LSP sent a snippet.
        -- 'super-tab' for tab to accept
        -- 'enter' for enter to accept
        -- 'none' for no mappings
        --
        -- For an understanding of why the 'default' preset is recommended,
        -- you will need to read `:help ins-completion`
        --
        -- No, but seriously. Please read `:help ins-completion`, it is really good!
        --
        -- All presets have the following mappings:
        -- <tab>/<s-tab>: move to right/left of your snippet expansion
        -- <c-space>: Open menu or open docs if already open
        -- <c-n>/<c-p> or <up>/<down>: Select next/previous item
        -- <c-e>: Hide menu
        -- <c-k>: Toggle signature help
        --
        -- See :h blink-cmp-config-keymap for defining your own keymap
        preset = 'default',
        -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
        --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
      },

      appearance = {
        -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
        -- Adjusts spacing to ensure icons are aligned
        nerd_font_variant = 'mono',
      },

      -- completion = {
      --   -- By default, you may press `<c-space>` to show the documentation.
      --   -- Optionally, set `auto_show = true` to show the documentation after a delay.
      --   documentation = { auto_show = false, auto_show_delay_ms = 500 },
      -- },
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
        -- default = { "lsp", "path", "snippets", "lazydev", "minuet" },

        per_filetype = {
          ['dap-repl'] = { 'dap', 'lsp' },
          ['dapui_watches'] = { 'dap', 'lsp' },
          ['dapui_hover'] = { 'dap' },
        },

        providers = {
          lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
          minuet = {
            name = 'minuet',
            module = 'minuet.blink',
            async = true,
            timeout_ms = 5000,
            score_offset = 50,
          },
          -- cmp-dap bridged through blink.compat
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

      -- Blink.cmp includes an optional, recommended rust fuzzy matcher,
      -- which automatically downloads a prebuilt binary when enabled.
      --
      -- By default, we use the Lua implementation instead, but you may enable
      -- the rust implementation via `'prefer_rust_with_warning'`
      --
      -- See :h blink-cmp-config-fuzzy for more information
      fuzzy = { implementation = 'prefer_rust_with_warning' },

      -- Shows a signature help window while you type arguments for a function
      signature = { enabled = true },
    }
  end,
}
