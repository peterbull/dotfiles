return {
  'echasnovski/mini.nvim',
  config = function()
    -- Better Around/Inside textobjects
    --
    -- Examples:
    --  - va)  - [V]isually select [A]round [)]paren
    --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
    --  - ci'  - [C]hange [I]nside [']quote
    require('mini.ai').setup { n_lines = 500 }

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    --
    -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
    -- - sd'   - [S]urround [D]elete [']quotes
    -- - sr)'  - [S]urround [R]eplace [)] [']
    require('mini.surround').setup()

    -- Simple and easy statusline.
    --  You could remove this setup call if you don't like it,
    --  and try some other statusline plugin
    local statusline = require 'mini.statusline'
    -- set use_icons to true if you have a Nerd Font
    statusline.setup { use_icons = vim.g.have_nerd_font }

    -- You can configure sections in the statusline by overriding their
    -- default behavior. For example, here we set the section for
    -- cursor location to LINE:COLUMN
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_location = function()
      return '%2l:%-2v'
    end

    -- ... and there is more!
    --  Check out: https://github.com/echasnovski/mini.nvim
    require('mini.files').setup()

    local yank_file_content = function()
      local MiniFiles = require 'mini.files'
      local entry = MiniFiles.get_fs_entry()
      if not entry then
        return vim.notify 'Cursor is not on valid entry'
      end

      local path = entry.path

      if entry.fs_type == 'file' then
        local lines = vim.fn.readfile(path)
        local content = '## ' .. path .. '\n\n' .. table.concat(lines, '\n')

        -- Append to clipboard
        local current_clipboard = vim.fn.getreg '+'
        local new_content = current_clipboard .. '\n' .. content .. '\n'
        vim.fn.setreg('+', new_content)

        vim.notify('Appended file content to clipboard: ' .. path)
      else
        -- for directories do nothing,
      end
    end

    vim.api.nvim_create_autocmd('User', {
      pattern = 'MiniFilesBufferCreate',
      callback = function(args)
        local buf_id = args.data.buf_id
        vim.keymap.set('n', 'gy', yank_file_content, { buffer = buf_id, desc = 'Yank path' })
      end,
    })
    vim.keymap.set('n', '<leader>e', function()
      local mini_files = require 'mini.files'
      mini_files.open(vim.api.nvim_buf_get_name(0), false)
      mini_files.reveal_cwd()
    end, { desc = 'Open mini file [E]xplorer' })
  end,
}
