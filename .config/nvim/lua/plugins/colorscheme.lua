return {
  'olimorris/onedarkpro.nvim',
  priority = 1000,
  config = function()
    require('onedarkpro').setup {
      highlights = {
        ['@lsp.typemod.variable.readonly.typescript'] = { fg = '#f0d090' },
        -- ['@type'] = { fg = '#f5e6b8' },
        ['@type.builtin'] = { fg = '#e0a070' },
        -- ['@type'] = { fg = '#fde68a', style = 'italic' }, -- Light gold
        ['@type'] = { fg = '#d8b4fe', style = 'italic' }, -- Light purple
        -- ['@type'] = { fg = '#7dd3fc' },
        -- ['@lsp.type.class'] = { fg = '#d8b4fe', style = 'italic' }, -- Light purple
        ['@lsp.typemod.variable.readonly.typescriptreact'] = { fg = '#e0de84' }, -- 25% lighter

        -- light blue arrow func
        ['@lsp.typemod.function.declaration.typescript'] = { fg = '#7dd3fc' },
        ['@lsp.typemod.function.readonly.typescript'] = { fg = '#7dd3fc' },

        -- python type hints
        ['@lsp.type.namespace.python'] = { fg = '#f0d090', style = 'italic' },
        ['@lsp.type.class.python'] = { fg = '#f0d090', style = 'italic' },
        Type = { fg = '#d19a66' },
      },

      styles = {
        functions = 'bold',
        comments = 'italic',
        variables = 'NONE',
        types = 'NONE',
      },
    }
    vim.cmd 'colorscheme onedark'
  end,
}
