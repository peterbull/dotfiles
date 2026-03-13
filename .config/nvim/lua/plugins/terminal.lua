return {
  'akinsho/toggleterm.nvim',
  version = '*',
  config = function()
    require('toggleterm').setup {
      size = function(term)
        if term.direction == 'horizontal' then
          return 15
        elseif term.direction == 'vertical' then
          return vim.o.columns * 0.4 -- 40% of screen width
        end
      end,
      open_mapping = [[<C-\>]], -- Default toggle with Ctrl+\
      hide_numbers = true,
      shade_terminals = false,
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      direction = 'vertical', -- Opens to the right
      close_on_exit = true,
      shell = vim.o.shell,
    }
    --
    -- -- Simple keymap to toggle terminal
    -- vim.keymap.set('n', '<leader>tt', '<cmd>ToggleTerm direction=vertical<CR>', { desc = 'Toggle Terminal (Right)' })
    -- vim.keymap.set('t', '<leader>tt', '<cmd>ToggleTerm<CR>', { desc = 'Toggle Terminal (Right)' })
    --
    -- Optional: Add a horizontal terminal toggle too
    vim.keymap.set('n', '<leader>th', '<cmd>ToggleTerm direction=horizontal<CR>', { desc = 'Toggle Terminal (Bottom)' })
  end,
}
