return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'master',
  lazy = false,
  build = ':TSUpdate',
  main = 'nvim-treesitter.configs',
  opts = {
    ensure_installed = {
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
      'json',
      'zig',
      'rust',
      'python',
      'ruby',
      'glsl',
      'graphql',
    },
    auto_install = true,
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = { 'ruby' },
    },
    indent = { enable = true, disable = { 'ruby' } },
  },
  keys = {
    {
      '<leader>ti',
      function()
        -- Check if InspectTree window is open
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'query' then
            -- Close the InspectTree window
            vim.api.nvim_win_close(win, true)
            return
          end
        end
        -- If not open, open it
        vim.cmd 'InspectTree'
      end,
      desc = 'Toggle Treesitter [I]nspect',
    },
  },
  config = function(_, opts)
    vim.opt.runtimepath:append(vim.fn.expand '~/peter-projects/tree-sitter-reef')
    vim.opt.runtimepath:append(vim.fn.expand '~/peter-projects/tree-sitter-mustache')

    local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
    parser_config.reef = {
      install_info = {
        url = vim.fn.expand '~/peter-projects/tree-sitter-reef',
        files = { 'src/parser.c' },
        branch = 'main',
      },
      filetype = 'reef',
    }

    parser_config.mustache = {
      install_info = {
        url = vim.fn.expand '~/peter-projects/tree-sitter-mustache',
        files = { 'src/parser.c', 'src/scanner.c' },
      },
      filetype = 'mustache',
    }

    require('nvim-treesitter.configs').setup(opts)

    -- Auto-start treesitter for reef and mustache files
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'reef', 'mustache' },
      callback = function(args)
        vim.treesitter.start(args.buf)
      end,
    })
  end,
}
