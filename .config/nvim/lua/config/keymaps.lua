-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- remap escape
vim.keymap.set('i', 'jk', '<ESC>', { noremap = true, silent = true })

-- quit trying to record macros when i sloppy-type

vim.keymap.set('n', 'q', '<Nop>', { noremap = true, silent = true })
vim.keymap.set('v', 'q', '<Nop>', { noremap = true, silent = true })

-- vim.keymap.set('i', 'jj', '<ESC>', { noremap = true, silent = true })
-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('n', 'gl', vim.diagnostic.open_float)

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
vim.keymap.set('t', 'jk', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
vim.keymap.set('n', '<C-h>', '<C-w>h', { remap = true })
vim.keymap.set('n', '<C-j>', '<C-w>j', { remap = true })
vim.keymap.set('n', '<C-k>', '<C-w>k', { remap = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { remap = true })

-- Window Resizing
vim.keymap.set('n', '<C-A-k>', ':res +5<CR>', { desc = 'Increase Window Height' })
vim.keymap.set('n', '<C-A-j>', ':res -5<CR>', { desc = 'Decrease Window Height' })
vim.keymap.set('n', '<C-A-l>', ':vert res +5<CR>', { desc = 'Increase Window Width' })
vim.keymap.set('n', '<C-A-h>', ':vert res -5<CR>', { desc = 'Decrease Window Width' })

-- NOTE: Some terminals have colliding keymaps or are not able to send distinct keycodes
vim.keymap.set('n', '<C-S-h>', '<C-w>H', { desc = 'Move window to the left' })
vim.keymap.set('n', '<C-S-l>', '<C-w>L', { desc = 'Move window to the right' })
vim.keymap.set('n', '<C-S-j>', '<C-w>J', { desc = 'Move window to the lower' })
vim.keymap.set('n', '<C-S-k>', '<C-w>K', { desc = 'Move window to the upper' })

vim.keymap.set('n', '<leader>bd', ':bd<CR>', { desc = '[D]elete Current Buffer' })
vim.keymap.set('n', '<leader>bo', ':%bd|edit#|bd#<CR>', { desc = '[D]elete All Other Buffers' })

-- Debug function
local function my_custom_function()
  print 'debug function executed!'
end

vim.keymap.set('n', '<leader>cf', my_custom_function, { desc = 'Run [C]ustom [F]unction' })
