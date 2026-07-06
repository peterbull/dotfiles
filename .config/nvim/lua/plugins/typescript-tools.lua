-- return {
--   'pmizio/typescript-tools.nvim',
--   dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
--   opts = {
--     settings = {
--       separate_diagnostic_server = true,
--       publish_diagnostic_on = 'insert_leave',
--       expose_as_code_action = {
--         'fix_all',
--         'add_missing_imports',
--         'remove_unused',
--         'remove_unused_imports',
--         'organize_imports',
--       },
--       tsserver_path = nil,
--       tsserver_plugins = {},
--       tsserver_max_memory = 'auto',
--       tsserver_format_options = {
--         allowIncompleteCompletions = false,
--         allowRenameOfImportPath = false,
--       },
--       tsserver_file_preferences = {
--         includeInlayParameterNameHints = 'all',
--         includeInlayParameterNameHintsWhenArgumentMatchesName = false,
--         includeInlayFunctionParameterTypeHints = true,
--         includeInlayVariableTypeHints = true,
--         includeInlayPropertyDeclarationTypeHints = true,
--         includeInlayFunctionLikeReturnTypeHints = true,
--         includeInlayEnumMemberValueHints = true,
--         -- Monorepo specific settings
--         includePackageJsonAutoImports = 'auto',
--         includeCompletionsForModuleExports = true,
--         includeAutomaticOptionalChainCompletions = true,
--       },
--       tsserver_locale = 'en',
--       complete_function_calls = false,
--       include_completions_with_insert_text = true,
--       code_lens = 'off',
--       disable_member_code_lens = true,
--       jsx_close_tag = {
--         enable = false,
--         filetypes = { 'javascriptreact', 'typescriptreact' },
--       },
--     },
--     -- Add root_dir function for monorepo support
--     root_dir = function(fname)
--       local util = require 'lspconfig.util'
--       return util.root_pattern('tsconfig.json', 'package.json', '.git')(fname)
--     end,
--   },
-- }

return {
	"yioneko/nvim-vtsls",
	lazy = false,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"neovim/nvim-lspconfig",
	},
	config = function()
		require("vtsls").config({
			refactor_auto_rename = true,
			refactor_move_to_file = {
				enable = true,
			},
		})

		-- Get capabilities from blink.cmp
		local capabilities = vim.tbl_deep_extend(
			"force",
			vim.lsp.protocol.make_client_capabilities(),
			require("blink.cmp").get_lsp_capabilities()
		)

		vim.lsp.config(
			"vtsls",
			vim.tbl_deep_extend("force", require("vtsls").lspconfig, {
				-- Prefer nearest tsconfig.json as root to avoid duplicate vtsls instances
				-- in monorepos (where both a package dir and the repo root have markers).
				-- Only fall back to package.json/.git if no tsconfig.json exists anywhere.
				root_dir = function(fname)
					local util = require("lspconfig.util")
					local tsconfig_root = util.root_pattern("tsconfig.json")(fname)
					if tsconfig_root then
						return tsconfig_root
					end
					return util.root_pattern("package.json", ".git")(fname)
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
							parameterNames = { enabled = "literals" },
							parameterTypes = { enabled = true },
							variableTypes = { enabled = true },
							propertyDeclarationTypes = { enabled = true },
							functionLikeReturnTypes = { enabled = true },
							enumMemberValues = { enabled = true },
						},
						updateImportsOnFileMove = {
							enabled = "always",
						},
						suggest = {
							completeFunctionCalls = true,
						},
						preferences = {
							includePackageJsonAutoImports = "on",
							importModuleSpecifier = "shortest",
						},
					},
					javascript = {
						inlayHints = {
							parameterNames = { enabled = "literals" },
						},
						updateImportsOnFileMove = {
							enabled = "always",
						},
					},
				},
			})
		)
		vim.lsp.enable("vtsls")
	end,
}
