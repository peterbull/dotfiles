return {
  'nvim-treesitter/nvim-treesitter',
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

    local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
    parser_config.reef = {
      install_info = {
        url = vim.fn.expand '~/peter-projects/tree-sitter-reef',
        files = { 'src/parser.c' },
        branch = 'main',
      },
      filetype = 'reef',
    }

    require('nvim-treesitter.configs').setup(opts)

    -- Auto-start treesitter for reef files
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'reef',
      callback = function(args)
        vim.treesitter.start(args.buf)
      end,
    })
  end,
}
