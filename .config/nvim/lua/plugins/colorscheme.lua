return {
  'olimorris/onedarkpro.nvim',
  priority = 1000,
  config = function()
    require('onedarkpro').setup {
      highlights = {
        -- underline instead of solid background
        LspReferenceText = { underline = true, sp = '#6c8ebf' },
        LspReferenceRead = { underline = true, sp = '#6c8ebf' },
        LspReferenceWrite = { underline = true, sp = '#6c8ebf' },

        ['@lsp.typemod.variable.readonly.typescript'] = { fg = '#f0d090' },
        ['@type.builtin'] = { fg = '#e0a070' },
        ['@type'] = { fg = '#d8b4fe', style = 'italic' },
        ['@lsp.typemod.variable.readonly.typescriptreact'] = { fg = '#e0de84' },

        -- light blue arrow func
        ['@lsp.typemod.function.declaration.typescript'] = { fg = '#7dd3fc' },
        ['@lsp.typemod.function.readonly.typescript'] = { fg = '#7dd3fc' },

        -- python type hints
        -- ['@lsp.type.namespace.python'] = { fg = '#f0d090', style = 'italic' },
        -- ['@lsp.type.class.python'] = { fg = '#f0d090', style = 'italic' },
        -- variables that are functions
        ['@lsp.type.variable.python'] = {},

        Type = { fg = '#d19a66' },

        -- reef
        ['@keyword.reef'] = { link = '@keyword' },
        ['@keyword.operator.reef'] = { link = '@keyword.operator' },
        ['@variable.builtin.reef'] = { link = '@variable.builtin' },
        ['@boolean.reef'] = { link = '@boolean' },
        ['@constant.builtin.reef'] = { link = '@constant.builtin' },
        ['@number.reef'] = { link = '@number' },
        ['@string.reef'] = { link = '@string' },
        ['@comment.reef'] = { link = '@comment' },
        ['@variable.reef'] = { link = '@variable' },
        ['@function.reef'] = { link = '@function' },
        ['@function.call.reef'] = { link = '@function.call' },
        ['@type.reef'] = { link = '@type' },
        ['@parameter.reef'] = { link = '@parameter' },
        ['@property.reef'] = { link = '@property' },
        ['@operator.reef'] = { link = '@operator' },
        ['@punctuation.delimiter.reef'] = { link = '@punctuation.delimiter' },

        ['@error.reef'] = { link = 'Error' },

        -- go
        -- ['@lsp.type.type.go'] = { fg = '#d19a66', style = 'italic' },
        -- ['@lsp.type.struct.go'] = { fg = '#e0a070' },
        -- ['@lsp.type.interface.go'] = { fg = '#e0a070', style = 'italic' },
        -- ['@lsp.type.function.go'] = { fg = '#7dd3fc', style = 'bold' },
        -- ['@lsp.type.method.go'] = { fg = '#7dd3fc' },
        -- ['@lsp.typemod.function.definition.go'] = { fg = '#7dd3fc', style = 'bold' },
        -- ['@lsp.typemod.method.definition.go'] = { fg = '#7dd3fc' },
        -- ['@lsp.type.namespace.go'] = { fg = '#a8c7fa' },
        -- ['@lsp.type.variable.go'] = {},
        -- ['@lsp.typemod.variable.readonly.go'] = { fg = '#f0d090' },
      },

      styles = {
        functions = 'bold',
        -- comments = 'italic',

        variables = 'NONE',
        types = 'NONE',
      },
    }
    vim.cmd 'colorscheme onedark'
  end,
}
