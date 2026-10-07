return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'master',
  lazy = false,
  build = ':TSUpdate',
  main = 'nvim-treesitter.configs',
  opts = {
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
    local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
    local available = {}
    local custom_parsers = {
      reef = { files = { 'src/parser.c' }, branch = 'main' },
      mustache = { files = { 'src/parser.c', 'src/scanner.c' } },
    }
    for _, lang in ipairs { 'reef', 'mustache' } do
      local info = custom_parsers[lang]
      info.url = vim.fn.expand('~/peter-projects/tree-sitter-' .. lang)
      local readable = true
      for _, file in ipairs(info.files) do
        readable = readable and vim.fn.filereadable(info.url .. '/' .. file) == 1
      end
      if readable then
        parser_config[lang] = { install_info = info, filetype = lang }
        available[#available + 1] = lang
      end
    end

    require('nvim-treesitter.configs').setup(opts)

    if #available > 0 then
      vim.api.nvim_create_autocmd('FileType', {
        pattern = available,
        callback = function(args)
          local ok, err = pcall(vim.treesitter.start, args.buf)
          if not ok then
            vim.notify('Optional Treesitter parser unavailable: ' .. tostring(err), vim.log.levels.WARN)
          end
        end,
      })
    end
  end,
}
