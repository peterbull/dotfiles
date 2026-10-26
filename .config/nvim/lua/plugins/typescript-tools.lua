return {
  'yioneko/nvim-vtsls',
  lazy = false,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'neovim/nvim-lspconfig',
  },
  config = function()
    require('vtsls').config {
      refactor_auto_rename = true,
      refactor_move_to_file = {
        enable = true,
      },
    }

    local capabilities = vim.tbl_deep_extend('force', vim.lsp.protocol.make_client_capabilities(), require('blink.cmp').get_lsp_capabilities())

    vim.lsp.config('vtsls', {
      -- Prefer nearest tsconfig.json as root to avoid duplicate vtsls instances
      -- in monorepos (where both a package dir and the repo root have markers).
      -- Only fall back to package.json/.git if no tsconfig.json exists anywhere.
      root_dir = function(bufnr, on_dir)
        local root = vim.fs.root(bufnr, 'tsconfig.json') or vim.fs.root(bufnr, { 'package.json', '.git' })
        if root then
          on_dir(root)
        end
      end,
      capabilities = capabilities,
      settings = {
        vtsls = {
          autoUseWorkspaceTsdk = true,
          enableMoveToFileCodeAction = true,
          experimental = {
            completion = {
              enableServerSideFuzzyMatch = true,
            },
          },
        },
        typescript = {
          inlayHints = {
            parameterNames = { enabled = 'literals' },
            parameterTypes = { enabled = true },
            variableTypes = { enabled = true },
            propertyDeclarationTypes = { enabled = true },
            functionLikeReturnTypes = { enabled = true },
            enumMemberValues = { enabled = true },
          },
          updateImportsOnFileMove = {
            enabled = 'always',
          },
          suggest = {
            completeFunctionCalls = true,
          },
          preferences = {
            includePackageJsonAutoImports = 'on',
            importModuleSpecifier = 'shortest',
          },
        },
        javascript = {
          inlayHints = {
            parameterNames = { enabled = 'literals' },
          },
          updateImportsOnFileMove = {
            enabled = 'always',
          },
        },
      },
    })
    vim.lsp.enable 'vtsls'
  end,
}
