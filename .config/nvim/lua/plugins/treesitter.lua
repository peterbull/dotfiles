return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,
  build = ':TSUpdate',
  opts = {
    install_dir = vim.fn.stdpath 'data' .. '/site-0.12',
    ensure_installed = {
      'asm',
      'bash',
      'c',
      'cpp',
      'diff',
      'html',
      'lua',
      'luadoc',
      'markdown',
      'markdown_inline',
      'query',
      'vim',
      'vimdoc',
      'javascript',
      'typescript',
      'tsx',
      'json',
      'zig',
      'rust',
      'python',
      'ruby',
      'go',
      'gomod',
      'gowork',
      'gosum',
      'yaml',
      'css',
      'embedded_template',
      'hcl',
      'toml',
      'glsl',
      'graphql',
    },
  },
  keys = {
    {
      '<leader>ti',
      function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].filetype == 'query' then
            vim.api.nvim_win_close(win, true)
            return
          end
        end
        vim.cmd 'InspectTree'
      end,
      desc = 'Toggle Treesitter [I]nspect',
    },
  },
  config = function(_, opts)
    local custom_parsers = {
      reef = { 'src/parser.c' },
      mustache = { 'src/parser.c', 'src/scanner.c' },
      bend2 = { 'src/parser.c', 'src/scanner.c' },
    }
    local function register_parsers()
      local parsers = require 'nvim-treesitter.parsers'
      for lang, files in pairs(custom_parsers) do
        local path = vim.fn.expand('~/peter-projects/tree-sitter-' .. lang)
        local readable = true
        for _, file in ipairs(files) do
          readable = readable and vim.fn.filereadable(path .. '/' .. file) == 1
        end
        if readable then
          parsers[lang] = { install_info = { path = path } }
          vim.treesitter.language.register(lang, lang == 'bend2' and 'bend' or lang)
        end
      end
    end
    local group = vim.api.nvim_create_augroup('dotfiles-treesitter', { clear = true })
    vim.api.nvim_create_autocmd('User', { group = group, pattern = 'TSUpdate', callback = register_parsers })
    register_parsers()

    local treesitter = require 'nvim-treesitter'
    treesitter.setup { install_dir = opts.install_dir }
    treesitter.install(opts.ensure_installed):await(function(err, success)
      if err or not success then
        vim.notify('Treesitter parser installation failed: ' .. tostring(err or 'see :messages'), vim.log.levels.ERROR)
      end
    end)

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      callback = function(args)
        local filetype = vim.bo[args.buf].filetype
        local lang = vim.treesitter.language.get_lang(filetype)
        if not lang or not require('nvim-treesitter.parsers')[lang] then
          return
        end
        local function start()
          if not vim.api.nvim_buf_is_valid(args.buf) or vim.bo[args.buf].filetype ~= filetype then
            return
          end
          local ok, err = pcall(vim.treesitter.start, args.buf, lang)
          if not ok then
            vim.notify('Treesitter: ' .. tostring(err), vim.log.levels.WARN)
            return
          end
          if filetype == 'ruby' then
            vim.bo[args.buf].syntax = 'ruby'
          elseif vim.treesitter.query.get(lang, 'indents') then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end
        if vim.fn.filereadable(opts.install_dir .. '/parser/' .. lang .. '.so') == 1 then
          start()
        else
          treesitter.install({ lang }):await(function(err, success)
            vim.schedule(function()
              if err or not success then
                vim.notify('Treesitter: failed to install ' .. lang .. ': ' .. tostring(err or 'see :messages'), vim.log.levels.ERROR)
              else
                start()
              end
            end)
          end)
        end
      end,
    })
  end,
}
