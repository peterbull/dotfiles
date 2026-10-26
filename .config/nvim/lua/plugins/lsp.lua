return {
  'neovim/nvim-lspconfig',

  dependencies = {
    { 'mason-org/mason.nvim', opts = {} },
    'mason-org/mason-lspconfig.nvim',
    'WhoIsSethDaniel/mason-tool-installer.nvim',

    { 'j-hui/fidget.nvim', opts = {} },

    'saghen/blink.cmp',
  },
  config = function()
    local file_ignore_patterns = {
      '_test%.go$',
      '%.test%.[jt]sx?$',
      '%.spec%.[jt]sx?$',
      '__tests__/',
      'test_.*%.py$',
      '.*_test%.py$',
    }
    local function man_page_actions(word, filetype)
      if word and word ~= '' then
        if filetype == 'ruby' then
          local output = vim.fn.system('ri --no-pager ' .. vim.fn.shellescape(word) .. ' | col -b')

          if vim.v.shell_error == 0 and output ~= '' then
            vim.cmd 'split'

            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_win_set_buf(0, buf)

            vim.bo[buf].filetype = 'man'

            vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, '\n'))
          else
            print('ri: Nothing known about ' .. word)
          end
        else
          vim.cmd('Man ' .. word)
        end
      else
        require('telescope.builtin').man_pages()
      end
    end

    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
      callback = function(event)
        local map = function(keys, func, desc, mode)
          mode = mode or 'n'
          vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
        end

        map('grn', vim.lsp.buf.rename, '[R]e[n]ame')

        map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })

        map('grr', function()
          require('telescope.builtin').lsp_references {
            file_ignore_patterns = file_ignore_patterns,
          }
        end, '[G]oto [R]eferences')

        map('gri', function()
          require('telescope.builtin').lsp_implementations {
            file_ignore_patterns = file_ignore_patterns,
          }
        end, '[G]oto [I]mplementation')

        map('grd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')

        map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

        map('<leader>cr', function()
          vim.lsp.codelens.enable(true, { bufnr = event.buf })
        end, '[C]ode Lens [R]efresh')
        map('<leader>cl', vim.lsp.codelens.run, '[C]ode [L]ens Run')
        map('gO', require('telescope.builtin').lsp_document_symbols, 'Open Document Symbols')

        map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Open Workspace Symbols')

        map('grt', require('telescope.builtin').lsp_type_definitions, '[G]oto [T]ype Definition')

        map('grm', function()
          local filetype = vim.bo.filetype
          local word = vim.fn.expand '<cword>'

          man_page_actions(word, filetype)
        end, '[G]oto [M]anual Page')

        map('grM', function()
          local filetype = vim.bo.filetype
          local word = vim.fn.expand '<cWORD>'
          word = word:gsub('[%.,;%(%)%[%]"\']+$', ''):gsub('^[%.,;%(%)%[%]"\']+', '')

          man_page_actions(word, filetype)
        end, '[G]oto [M]anual Page')

        map('grs', function()
          local clients = vim.lsp.get_clients { bufnr = vim.api.nvim_get_current_buf() }
          local vtsls_client = nil

          for _, client in ipairs(clients) do
            if client.name == 'vtsls' then
              vtsls_client = client
              break
            end
          end

          if vtsls_client then
            local winnr = vim.api.nvim_get_current_win()
            local params = vim.lsp.util.make_position_params(winnr, vtsls_client.offset_encoding)

            vim.lsp.buf_request(0, 'workspace/executeCommand', {
              command = 'typescript.goToSourceDefinition',
              arguments = { params.textDocument.uri, params.position },
            }, function(err, result, ctx, config)
              if err then
                vim.notify('[vtsls]: ' .. tostring(err), vim.log.levels.ERROR)
                return
              end

              local locations = result
              if locations == vim.NIL or not locations or vim.tbl_isempty(locations) then
                vim.notify('No source definition found', vim.log.levels.WARN)
                return
              elseif #locations == 1 then
                vim.lsp.util.show_document(locations[1], vtsls_client.offset_encoding, { reuse_win = false, focus = true })
              else
                local items = vim.lsp.util.locations_to_items(locations, vtsls_client.offset_encoding)
                vim.fn.setqflist({}, ' ', {
                  title = 'TS Source Definitions',
                  items = items,
                  context = ctx,
                })
                vim.api.nvim_command 'botright copen'
              end
            end)
          else
            require('telescope.builtin').lsp_definitions()
          end
        end, '[G]oto [S]ource Definition')

        local client = vim.lsp.get_client_by_id(event.data.client_id)

        if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
          map('<leader>th', function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
          end, '[T]oggle Inlay [H]ints')
        end

        local excluded_filetypes = { 'lua', 'python' }

        if
          not vim.tbl_contains(excluded_filetypes, vim.bo[event.buf].filetype)
          and client
          and client:supports_method(vim.lsp.protocol.Methods.textDocument_codeLens, event.buf)
        then
          vim.lsp.codelens.enable(true, { bufnr = event.buf })
        end
      end,
    })

    vim.diagnostic.config {
      severity_sort = true,
      float = { border = 'rounded', source = 'if_many' },
      underline = { severity = vim.diagnostic.severity.ERROR },
      signs = vim.g.have_nerd_font and {
        text = {
          [vim.diagnostic.severity.ERROR] = '󰅚 ',
          [vim.diagnostic.severity.WARN] = '󰀪 ',
          [vim.diagnostic.severity.INFO] = '󰋽 ',
          [vim.diagnostic.severity.HINT] = '󰌶 ',
        },
      } or {},
      virtual_text = {
        source = 'if_many',
        spacing = 2,
        format = function(diagnostic)
          local diagnostic_message = {
            [vim.diagnostic.severity.ERROR] = diagnostic.message,
            [vim.diagnostic.severity.WARN] = diagnostic.message,
            [vim.diagnostic.severity.INFO] = diagnostic.message,
            [vim.diagnostic.severity.HINT] = diagnostic.message,
          }
          return diagnostic_message[diagnostic.severity]
        end,
      },
    }

    local capabilities = require('blink.cmp').get_lsp_capabilities()

    local servers = {
      vtsls = false, -- managed separately in typescript-tools.lua (monorepo root_dir)
      clangd = {},
      gopls = {},

      ty = {
        settings = {}, -- before_init mutates the settings table already held by the client.
        before_init = function(_, config)
          local ok, selector = pcall(require, 'venv-selector')
          local venv = ok and selector.venv() or nil
          if venv then
            config.settings.python = config.settings.python or {}
            config.settings.python.pythonPath = venv .. '/bin/python'
          end
        end,
      },

      html = {
        filetypes = { 'html' },
        init_options = {
          configurationSection = { 'html', 'css', 'javascript' },
          embeddedLanguages = {
            css = true,
            javascript = true,
          },
        },
      },

      helm_ls = {
        settings = {
          ['helm-ls'] = {
            yamlls = {
              path = 'yaml-language-server',
            },
          },
        },
      },
      emmet_language_server = {
        filetypes = { 'html', 'css' },
      },
      graphql = {
        filetypes = { 'graphql', 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
      },
      lua_ls = {
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
            },
            diagnostics = {
              globals = { 'vim' },
            },
            workspace = {
              checkThirdParty = false,
              library = {
                vim.env.VIMRUNTIME,
                '${3rd}/luv/library',
              },
            },
            completion = {
              callSnippet = 'Replace',
            },
            telemetry = {
              enable = false,
            },
            codeLens = {
              enable = true,
            },
            hint = {
              enable = true,
              semicolon = 'Disable',
            },
          },
        },
      },
      zls = {
        cmd = { 'zls' },
        settings = {
          zls = {
            enable_build_on_save = true,
          },
        },
      },
      terraformls = {
        filetypes = { 'terraform', 'tf', 'terraform-vars', 'hcl' },
        settings = {
          terraform = {
            validate = {
              enable = true,
            },
            format = {
              enable = true,
            },
          },
        },
      },
      ruby_lsp = false,
    }

    local active_servers = {}
    for name, server in pairs(servers) do
      if server ~= false then
        server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
        vim.lsp.config(name, server)
        active_servers[#active_servers + 1] = name
      end
    end
    table.sort(active_servers)
    local ensure_installed = require('config.mason-tools').ensure_installed()
    vim.list_extend(ensure_installed, active_servers)
    require('mason-tool-installer').setup {
      ensure_installed = ensure_installed,
      integrations = { ['mason-lspconfig'] = true, ['mason-null-ls'] = false, ['mason-nvim-dap'] = false },
    }

    vim.lsp.config('gopls', {
      capabilities = vim.tbl_deep_extend('force', {}, capabilities),
      on_attach = function(client, _)
        if not client.server_capabilities.semanticTokensProvider then
          local semantic = client.config.capabilities.textDocument.semanticTokens
          client.server_capabilities.semanticTokensProvider = {
            full = true,
            legend = {
              tokenTypes = semantic.tokenTypes,
              tokenModifiers = semantic.tokenModifiers,
            },
            range = true,
          }
        end
      end,
      settings = {
        gopls = {
          semanticTokens = true,
          hints = {
            assignVariableTypes = true,
            compositeLiteralFields = true,
            compositeLiteralTypes = true,
            constantValues = true,
            functionTypeParameters = true,
            parameterNames = true,
            rangeVariableTypes = true,
          },
          analyses = {
            unusedparams = true,
          },
          staticcheck = true,
          gofumpt = true,
        },
      },
    })
    vim.lsp.config('ruby_lsp', {
      cmd = { 'mise', 'exec', '--', 'ruby-lsp' },
      filetypes = { 'ruby', 'eruby', 'erb' },
      root_markers = { 'Gemfile', '.ruby-version' },
      capabilities = capabilities,
      on_attach = function(client, bufnr)
        vim.lsp.commands['rubyLsp.openFile'] = function(cmd, _)
          local uri_frag = cmd.arguments[1][1]
          local uri, line = uri_frag:match '^(.+)#L(%d+)$'
          if not uri then
            uri = uri_frag
          end
          local buf = vim.uri_to_bufnr(uri)
          vim.fn.bufload(buf)
          vim.api.nvim_set_option_value('buflisted', true, { buf = buf })
          vim.api.nvim_set_current_buf(buf)
          vim.api.nvim_win_set_cursor(0, { tonumber(line) or 1, 0 })
        end
      end,
      init_options = {
        formatter = 'auto',
        enabledFeatures = {
          codeActions = true,
          codeLens = true,
          completion = true,
          definition = true,
          diagnostics = true,
          documentHighlights = true,
          documentLink = true,
          documentSymbols = true,
          foldingRanges = true,
          formatting = true,
          hover = true,
          inlayHint = true,
          onTypeFormatting = true,
          selectionRanges = true,
          semanticHighlighting = true,
          signatureHelp = true,
          typeHierarchy = true,
          workspaceSymbol = true,
        },
        experimentalFeaturesEnabled = true,
      },
    })

    -- Capture uses local tooling; other projects opt in through sorbet/config.
    local sorbet = require 'config.sorbet'
    local sorbet_noise_codes = { ['7003'] = true, [7003] = true }
    local publish_diagnostics = vim.lsp.handlers['textDocument/publishDiagnostics']

    vim.lsp.config('sorbet', {
      cmd = sorbet.cmd,
      cmd_env = { SRB_SKIP_GEM_RBIS = '1' },
      filetypes = { 'ruby' },
      root_dir = sorbet.root_dir,
      workspace_required = true,
      capabilities = vim.tbl_deep_extend('force', {}, capabilities),
      on_attach = function(_, bufnr)
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = bufnr, desc = 'Sorbet hover' })
      end,
      handlers = {
        ['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
          if result and result ~= vim.NIL and type(result.diagnostics) == 'table' then
            result.diagnostics = vim.tbl_filter(function(d)
              return not sorbet_noise_codes[d.code]
            end, result.diagnostics)
          end
          publish_diagnostics(err, result, ctx, config)
        end,
      },
    })

    vim.lsp.enable 'ruby_lsp'
    vim.lsp.enable 'sorbet'
    require('mason-lspconfig').setup {
      ensure_installed = {}, -- mason-tool-installer owns installation.
      automatic_enable = active_servers,
    }
  end,
}
