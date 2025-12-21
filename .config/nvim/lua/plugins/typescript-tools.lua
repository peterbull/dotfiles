return {
  'pmizio/typescript-tools.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  opts = {
    settings = {
      separate_diagnostic_server = true,
      publish_diagnostic_on = 'insert_leave',
      expose_as_code_action = {
        'fix_all',
        'add_missing_imports',
        'remove_unused',
        'remove_unused_imports',
        'organize_imports',
      },
      tsserver_path = nil,
      tsserver_plugins = {},
      tsserver_max_memory = 'auto',
      tsserver_format_options = {
        allowIncompleteCompletions = false,
        allowRenameOfImportPath = false,
      },
      tsserver_file_preferences = {
        includeInlayParameterNameHints = 'all',
        includeInlayParameterNameHintsWhenArgumentMatchesName = false,
        includeInlayFunctionParameterTypeHints = true,
        includeInlayVariableTypeHints = true,
        includeInlayPropertyDeclarationTypeHints = true,
        includeInlayFunctionLikeReturnTypeHints = true,
        includeInlayEnumMemberValueHints = true,
        -- Monorepo specific settings
        includePackageJsonAutoImports = 'auto',
        includeCompletionsForModuleExports = true,
        includeAutomaticOptionalChainCompletions = true,
      },
      tsserver_locale = 'en',
      complete_function_calls = false,
      include_completions_with_insert_text = true,
      code_lens = 'off',
      disable_member_code_lens = true,
      jsx_close_tag = {
        enable = false,
        filetypes = { 'javascriptreact', 'typescriptreact' },
      },
    },
    -- Add root_dir function for monorepo support
    root_dir = function(fname)
      local util = require 'lspconfig.util'
      return util.root_pattern('tsconfig.json', 'package.json', '.git')(fname)
    end,
  },
}
