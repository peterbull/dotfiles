--[[

=====================================================================
==================== READ THIS BEFORE CONTINUING ====================
=====================================================================
========                                    .-----.          ========
========         .----------------------.   | === |          ========
========         |.-""""""""""""""""""-.|   |-----|          ========
========         ||                    ||   | === |          ========
========         ||   KICKSTART.NVIM   ||   |-----|          ========
========         ||                    ||   | === |          ========
========         ||                    ||   |-----|          ========
========         ||:Tutor              ||   |:::::|          ========
========         |'-..................-'|   |____o|          ========
========         `"")----------------(""`   ___________      ========
========        /::::::::::|  |::::::::::\  \ no mouse \     ========
========       /:::========|  |==hjkl==:::\  \ required \    ========
========      '""""""""""""'  '""""""""""""'  '""""""""""'   ========
========                                                     ========
=====================================================================
=====================================================================

What is Kickstart?

  Kickstart.nvim is *not* a distribution.

  Kickstart.nvim is a starting point for your own configuration.
    The goal is that you can read every line of code, top-to-bottom, understand
    what your configuration is doing, and modify it to suit your needs.

    Once you've done that, you can start exploring, configuring and tinkering to
    make Neovim your own! That might mean leaving Kickstart just the way it is for a while
    or immediately breaking it into modular pieces. It's up to you!

    If you don't know anything about Lua, I recommend taking some time to read through
    a guide. One possible example which will only take 11-15 minutes:
      - https://learnxinyminutes.com/docs/lua/

    After understanding a bit more about Lua, you can use `:help lua-guide` as a
    reference for how Neovim integrates Lua.
    - :help lua-guide
    - (or HTML version): https://neovim.io/doc/user/lua-guide.html

Kickstart Guide:

  TODO: The very first thing you should do is to run the command `:Tutor` in Neovim.

    If you don't know what this means, type the following:
      - <escape key>
      - :
      - Tutor
      - <enter key>

    (If you already know the Neovim basics, you can skip this step.)

  Once you've completed that, you can continue working through **AND READING** the rest
  of the kickstart init.lua.

  Next, run AND READ `:help`.
    This will open up a help window with some basic information
    about reading, navigating and searching the builtin help documentation.

    This should be the first place you go to look when you're stuck or confused
    with something. It's one of my favorite Neovim features.

    MOST IMPORTANTLY, we provide a keymap "<space>sh" to [s]earch the [h]elp documentation,
    which is very useful when you're not exactly sure of what you're looking for.

  I have left several `:help X` comments throughout the init.lua
    These are hints about where to find more information about the relevant settings,
    plugins or Neovim features used in Kickstart.

   NOTE: Look for lines like this

    Throughout the file. These are for you, the reader, to help you understand what is happening.
    Feel free to delete them once you know what you're doing, but they should serve as a guide
    for when you are first encountering a few different constructs in your Neovim config.

If you experience any errors while trying to install kickstart, run `:checkhealth` for more info.

I hope you enjoy your Neovim journey,
- TJ

P.S. You can delete this when you're done too. It's your config now! :)
--]]

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

--- https://github.com/fredrikaverpil/dotfiles/blob/82b161d397d27772e2eb34422058df5fd44b06a7/nvim-fredrik/lua/fredrik/init.lua#L7
---@diagnostic disable-next-line: undefined-global
if init_debug then
  local osvpath = vim.fn.stdpath 'data' .. '/lazy/one-small-step-for-vimkind'
  vim.opt.rtp:prepend(osvpath)
  require('osv').launch { port = 8086, blocking = true }
end

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = false

-- [[ Setting options ]]
-- See `:help vim.o`
-- NOTE: You can change these options as you wish!
--  For more options, you can see `:help option-list`

-- Make line numbers default
vim.o.number = true
-- You can also add relative line numbers, to help with jumping.
--  Experiment for yourself to see if you like it!
-- vim.o.relativenumber = true

-- Enable mouse mode, can be useful for resizing splits for example!
vim.o.mouse = 'a'

-- Don't show the mode, since it's already in the status line
vim.o.showmode = false

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function()
  vim.o.clipboard = 'unnamedplus'
end)

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.o.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250

-- Decrease mapped sequence wait time
vim.o.timeoutlen = 300

-- Configure how new splits should be opened
vim.o.splitright = true
vim.o.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
--
--  Notice listchars is set using `vim.opt` instead of `vim.o`.
--  It is very similar to `vim.o` but offers an interface for conveniently interacting with tables.
--   See `:help lua-options`
--   and `:help lua-options-guide`
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.o.inccommand = 'split'

-- Show which line your cursor is on
vim.o.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.o.scrolloff = 10

-- if performing an operation that would fail due to unsaved changes in the buffer (like `:q`),
-- instead raise a dialog asking if you wish to save the current file(s)
-- See `:help 'confirm'`
vim.o.confirm = true

-- base language configs
vim.g.python_recommended_style = 0
vim.g.rust_recommended_style = 0
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.shiftwidth = 2
vim.opt.expandtab = true

-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

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
vim.g.python3_host_prog = vim.fn.expand '~/.virtualenvs/nvim/bin/python3'
-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

vim.filetype.add {
  extension = {
    edge = 'edge',
  },
}

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end

-- Debug function
local function my_custom_function()
  print 'debug function executed!'
end

vim.keymap.set('n', '<leader>cf', my_custom_function, { desc = 'Run [C]ustom [F]unction' })
---
---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

-- [[ Configure and install plugins ]]
--
--  To check the current status of your plugins, run
--    :Lazy
--
--  You can press `?` in this menu for help. Use `:q` to close the window
--
--  To update plugins you can run
--    :Lazy update
--
-- NOTE: Here is where you install your plugins.
require('lazy').setup({
  -- NOTE: Plugins can be added with a link (or for a github repo: 'owner/repo' link).
  'NMAC427/guess-indent.nvim', -- Detect tabstop and shiftwidth automatically

  -- NOTE: Plugins can also be added by using a table,
  -- with the first argument being the link and the following
  -- keys can be used to configure plugin behavior/loading/etc.
  --
  -- Use `opts = {}` to automatically pass options to a plugin's `setup()` function, forcing the plugin to be loaded.
  --

  -- Alternatively, use `config = function() ... end` for full control over the configuration.
  -- If you prefer to call `setup` explicitly, use:
  --    {
  --        'lewis6991/gitsigns.nvim',
  --        config = function()
  --            require('gitsigns').setup({
  --                -- Your gitsigns configuration here
  --            })
  --        end,
  --    }
  --
  -- Here is a more advanced example where we pass configuration
  -- options to `gitsigns.nvim`.
  --
  -- See `:help gitsigns` to understand what the configuration keys do
  { -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
    },

    keys = {
      {
        '<leader>grh',
        function()
          require('gitsigns').reset_hunk()
        end,
        desc = 'Reset Hunk',
      },
      {
        '<leader>gb',
        function()
          local gitsigns = require 'gitsigns'
          gitsigns.blame()
        end,
        desc = '[B]lame for Current Buffer',
      },
    },
  },

  -- NOTE: Plugins can also be configured to run Lua code when they are loaded.
  --
  -- This is often very useful to both group configuration, as well as handle
  -- lazy loading plugins that don't need to be loaded immediately at startup.
  --
  -- For example, in the following configuration, we use:
  --  event = 'VimEnter'
  --
  -- which loads which-key before all the UI elements are loaded. Events can be
  -- normal autocommands events (`:help autocmd-events`).
  --
  -- Then, because we use the `opts` key (recommended), the configuration runs
  -- after the plugin has been loaded as `require(MODULE).setup(opts)`.

  { -- Useful plugin to show you pending keybinds.
    'folke/which-key.nvim',
    event = 'VimEnter', -- Sets the loading event to 'VimEnter'
    opts = {
      -- delay between pressing a key and opening which-key (milliseconds)
      -- this setting is independent of vim.o.timeoutlen
      delay = 0,
      icons = {
        -- set icon mappings to true if you have a Nerd Font
        mappings = vim.g.have_nerd_font,
        -- If you are using a Nerd Font: set icons.keys to an empty table which will use the
        -- default which-key.nvim defined Nerd Font icons, otherwise define a string table
        keys = vim.g.have_nerd_font and {} or {
          Up = '<Up> ',
          Down = '<Down> ',
          Left = '<Left> ',
          Right = '<Right> ',
          C = '<C-…> ',
          M = '<M-…> ',
          D = '<D-…> ',
          S = '<S-…> ',
          CR = '<CR> ',
          Esc = '<Esc> ',
          ScrollWheelDown = '<ScrollWheelDown> ',
          ScrollWheelUp = '<ScrollWheelUp> ',
          NL = '<NL> ',
          BS = '<BS> ',
          Space = '<Space> ',
          Tab = '<Tab> ',
          F1 = '<F1>',
          F2 = '<F2>',
          F3 = '<F3>',
          F4 = '<F4>',
          F5 = '<F5>',
          F6 = '<F6>',
          F7 = '<F7>',
          F8 = '<F8>',
          F9 = '<F9>',
          F10 = '<F10>',
          F11 = '<F11>',
          F12 = '<F12>',
        },
      },

      -- Document existing key chains
      spec = {
        { '<leader>s', group = '[S]earch' },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>d', group = '[D]ebug' },
        { '<leader>b', group = '[B]uffer' },
        { '<leader>h', group = '[H]arpoon' },
        { '<leader>m', group = '[M]olten' },
        { '<leader>r', group = '[R]EPL' },
        { '<leader>c', group = '[C]ustom' },
      },
    },
  },

  -- NOTE: Plugins can specify dependencies.
  --
  -- The dependencies are proper plugin specifications as well - anything
  -- you do for a plugin at the top level, you can do for a dependency.
  --
  -- Use the `dependencies` key to specify the dependencies of a particular plugin

  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { -- If encountering errors, see telescope-fzf-native README for installation instructions
        'nvim-telescope/telescope-fzf-native.nvim',

        -- `build` is used to run some command when the plugin is installed/updated.
        -- This is only run then, not every time Neovim starts up.
        build = 'make',

        -- `cond` is a condition used to determine whether this plugin should be
        -- installed and loaded.
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },

      -- Useful for getting pretty icons, but requires a Nerd Font.
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      -- Telescope is a fuzzy finder that comes with a lot of different things that
      -- it can fuzzy find! It's more than just a "file finder", it can search
      -- many different aspects of Neovim, your workspace, LSP, and more!
      --
      -- The easiest way to use Telescope, is to start by doing something like:
      --  :Telescope help_tags
      --
      -- After running this command, a window will open up and you're able to
      -- type in the prompt window. You'll see a list of `help_tags` options and
      -- a corresponding preview of the help.
      --
      -- Two important keymaps to use while in Telescope are:
      --  - Insert mode: <c-/>
      --  - Normal mode: ?
      --
      -- This opens a window that shows you all of the keymaps for the current
      -- Telescope picker. This is really useful to discover what Telescope can
      -- do as well as how to actually do it!

      -- [[ Configure Telescope ]]
      -- See `:help telescope` and `:help telescope.setup()`
      require('telescope').setup {
        -- You can put your default mappings / updates / etc. in here
        --  All the info you're looking for is in `:help telescope.setup()`
        --
        -- defaults = {
        --   mappings = {
        --     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
        --   },
        -- },
        -- pickers = {}
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown {
              layout_config = { width = 0.8 },
            },
          },
        },
      }

      -- Enable Telescope extensions if they are installed
      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      -- See `:help telescope.builtin`
      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

      vim.keymap.set('n', '<leader>saf', function()
        builtin.find_files { hidden = true, no_ignore = true }
      end, { desc = '[S]earch [A]ll [F]iles, includes hidden' })

      vim.keymap.set('n', '<leader>sag', function()
        builtin.live_grep {
          additional_args = function()
            return {
              '--hidden',
              '--no-ignore',
              '--glob',
              '!**/node_modules/**',
              '--glob',
              '!**/.venv/**',
              '--glob',
              '!**/.git/**',
              '--glob',
              '!**/dist/**',
              '--glob',
              '!**/build/**',
              '--glob',
              '!**/__pycache__/**',
              '--glob',
              '!**/.next/**',
              '--glob',
              '!**/coverage/**',
            }
          end,
        }
      end, { desc = '[S]earch in [A]ll Files by [G]rep' })

      -- Slightly advanced example of overriding default behavior and theme
      vim.keymap.set('n', '<leader>/', function()
        -- You can pass additional configuration to Telescope to change the theme, layout, etc.
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      -- It's also possible to pass additional configuration options.
      --  See `:help telescope.builtin.live_grep()` for information about particular keys
      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })

      -- Shortcut for searching your Neovim configuration files
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  -- LSP Plugins
  {
    -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
    -- used for completion, annotations and signatures of Neovim apis
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when the `vim.uv` word is found
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },
  {
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
  },
  {
    -- Main LSP Configuration
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      -- Mason must be loaded before its dependents so we need to set it up here.
      -- NOTE: `opts = {}` is the same as calling `require('mason').setup({})`
      { 'mason-org/mason.nvim', opts = {} },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- Useful status updates for LSP.
      { 'j-hui/fidget.nvim', opts = {} },

      -- Allows extra capabilities provided by blink.cmp
      'saghen/blink.cmp',
    },
    config = function()
      -- Brief aside: **What is LSP?**
      --
      -- LSP is an initialism you've probably heard, but might not understand what it is.
      --
      -- LSP stands for Language Server Protocol. It's a protocol that helps editors
      -- and language tooling communicate in a standardized fashion.
      --
      -- In general, you have a "server" which is some tool built to understand a particular
      -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
      -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
      -- processes that communicate with some "client" - in this case, Neovim!
      --
      -- LSP provides Neovim with features like:
      --  - Go to definition
      --  - Find references
      --  - Autocompletion
      --  - Symbol Search
      --  - and more!
      --
      -- Thus, Language Servers are external tools that must be installed separately from
      -- Neovim. This is where `mason` and related plugins come into play.
      --
      -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
      -- and elegantly composed help section, `:help lsp-vs-treesitter`

      --  This function gets run when an LSP attaches to a particular buffer.
      --    That is to say, every time a new file is opened that is associated with
      --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
      --    function will be executed to configure the current buffer
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- NOTE: Remember that Lua is a real programming language, and as such it is possible
          -- to define small helper and utility functions so you don't have to repeat yourself.
          --
          -- In this case, we create a function that lets us more easily define mappings specific
          -- for LSP related items. It sets the mode, buffer and description for us each time.
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Rename the variable under your cursor.
          --  Most Language Servers support renaming across files, etc.
          map('grn', vim.lsp.buf.rename, '[R]e[n]ame')

          -- Execute a code action, usually your cursor needs to be on top of an error
          -- or a suggestion from your LSP for this to activate.
          map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })

          -- Find references for the word under your cursor.
          map('grr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

          -- Jump to the implementation of the word under your cursor.
          --  Useful when your language has ways of declaring types without an actual implementation.
          map('gri', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')

          -- Jump to the definition of the word under your cursor.
          --  This is where a variable was first declared, or where a function is defined, etc.
          --  To jump back, press <C-t>.
          map('grd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')

          -- WARN: This is not Goto Definition, this is Goto Declaration.
          --  For example, in C this would take you to the header.
          map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- Fuzzy find all the symbols in your current document.
          --  Symbols are things like variables, functions, types, etc.
          map('gO', require('telescope.builtin').lsp_document_symbols, 'Open Document Symbols')

          -- Fuzzy find all the symbols in your current workspace.
          --  Similar to document symbols, except searches over your entire project.
          map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Open Workspace Symbols')

          -- Jump to the type of the word under your cursor.
          --  Useful when you're not sure what type a variable is and you want to see
          --  the definition of its *type*, not where it was *defined*.
          map('grt', require('telescope.builtin').lsp_type_definitions, '[G]oto [T]ype Definition')

          map('grm', function()
            local word = vim.fn.expand '<cword>'
            if word and word ~= '' then
              vim.cmd('Man ' .. word)
            else
              require('telescope.builtin').man_pages()
            end
          end, '[G]oto [M]anual Page')
          map('grs', function()
            -- go to source def in ts tools
            local clients = vim.lsp.get_clients { bufnr = event.buf }
            local has_tsserver = false

            for _, client in ipairs(clients) do
              if client.name == 'typescript-tools' or client.name == 'tsserver' then
                has_tsserver = true
                break
              end
            end

            if has_tsserver then
              vim.cmd 'TSToolsGoToSourceDefinition'
            else
              require('telescope.builtin').lsp_definitions()
            end
          end, '[G]oto [S]ource Definition')
          --
          -- This function resolves a difference between neovim nightly (version 0.11) and stable (version 0.10)
          ---@param client vim.lsp.Client
          ---@param method vim.lsp.protocol.Method
          ---@param bufnr? integer some lsp support methods only in specific files
          ---@return boolean
          local function client_supports_method(client, method, bufnr)
            if vim.fn.has 'nvim-0.11' == 1 then
              return client:supports_method(method, bufnr)
            else
              return client.supports_method(method, { bufnr = bufnr })
            end
          end

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- The following code creates a keymap to toggle inlay hints in your
          -- code, if the language server you are using supports them
          --
          -- This may be unwanted, since they displace some of your code
          if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- Diagnostic Config
      -- See :help vim.diagnostic.Opts
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

      -- LSP servers and clients are able to communicate to each other what features they support.
      --  By default, Neovim doesn't support everything that is in the LSP specification.
      --  When you add blink.cmp, luasnip, etc. Neovim now has *more* capabilities.
      --  So, we create new capabilities with blink.cmp, and then broadcast that to the servers.
      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- Enable the following language servers
      --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
      --
      --  Add any additional override configuration in the following tables. Available keys are:
      --  - cmd (table): Override the default command used to start the server
      --  - filetypes (table): Override the default list of associated filetypes for the server
      --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
      --  - settings (table): Override the default settings passed when initializing the server.
      --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
      local servers = {
        clangd = {},
        -- gopls = {},
        pyright = {},
        rust_analyzer = false,
        -- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
        --
        -- Some languages (like typescript) have entire language plugins that can be useful:
        --    https://github.com/pmizio/typescript-tools.nvim
        --
        -- But for many setups, the LSP (`ts_ls`) will work just fine
        --
        -- ts_ls = false, -- using typescript tools now

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

        emmet_language_server = {
          filetypes = { 'html', 'css' },
        },

        lua_ls = {
          -- cmd = { ... },
          -- filetypes = { ... },
          -- capabilities = {},
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },

        terraformls = {
          filetypes = { 'terraform', 'tf', 'terraform-vars' },
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
      }

      -- Ensure the servers and tools above are installed
      --
      -- To check the current status of installed tools and/or manually install
      -- other tools, you can run
      --    :Mason
      --
      -- You can press `g?` for help in this menu.
      --
      -- `mason` had to be setup earlier: to configure its options see the
      -- `dependencies` table for `nvim-lspconfig` above.
      --
      -- You can add other tools here that you want Mason to install
      -- for you, so that they are available from within Neovim.
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        'stylua', -- Used to format Lua code
      })
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        ensure_installed = {}, -- explicitly set to an empty table (Kickstart populates installs via mason-tool-installer)
        automatic_installation = false,
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            -- This handles overriding only values explicitly passed
            -- by the server configuration above. Useful when disabling
            -- certain features of an LSP (for example, turning off formatting for ts_ls)
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },
  { -- Autoformat
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function()
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- Disable "format_on_save lsp_fallback" for languages that don't
        -- have a well standardized coding style. You can add additional
        -- languages here or re-enable it for the disabled ones.
        local disable_filetypes = { c = true, cpp = true }
        if disable_filetypes[vim.bo[bufnr].filetype] then
          return nil
        else
          return {
            timeout_ms = 500,
            lsp_format = 'fallback',
          }
        end
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        -- Conform can also run multiple formatters sequentially
        python = { 'isort', 'black' },
        --
        -- You can use 'stop_after_first' to run the first available formatter from the list
        javascript = { 'prettierd', 'prettier', stop_after_first = true },
        typescript = { 'prettierd', 'prettier', stop_after_first = true },
        typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        rust = { 'rustfmt', lsp_format = 'fallback' },
        zig = { 'zigfmt' },
        sh = { 'shfmt' },
        bash = { 'shfmt' },
      },
    },
  },

  { -- Autocompletion
    'saghen/blink.cmp',
    event = 'VimEnter',
    version = '1.*',
    dependencies = {
      -- Snippet Engine
      {
        'L3MON4D3/LuaSnip',
        version = '2.*',
        build = (function()
          -- Build Step is needed for regex support in snippets.
          -- This step is not supported in many windows environments.
          -- Remove the below condition to re-enable on windows.
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = {
          -- `friendly-snippets` contains a variety of premade snippets.
          --    See the README about individual language/framework/plugin snippets:
          --    https://github.com/rafamadriz/friendly-snippets
          {
            'rafamadriz/friendly-snippets',
            config = function()
              require('luasnip.loaders.from_vscode').lazy_load()
            end,
          },
        },
        opts = {

          menu = {

            draw = {
              columns = {
                { 'kind_icon', 'label', gap = 1 },
                { 'kind' },
              },
              components = {
                kind_icon = {
                  text = function(item)
                    local kind = require('lspkind').symbol_map[item.kind] or ''
                    return kind .. ' '
                  end,
                  highlight = 'CmpItemKind',
                },
                label = {
                  text = function(item)
                    return item.label
                  end,
                  highlight = 'CmpItemAbbr',
                },
                kind = {
                  text = function(item)
                    return item.kind
                  end,
                  highlight = 'CmpItemKind',
                },
              },
            },
          },
        },
      },
      'folke/lazydev.nvim',
    },
    --- @module 'blink.cmp'
    --- @type blink.cmp.Config
    opts = {
      keymap = {
        -- 'default' (recommended) for mappings similar to built-in completions
        --   <c-y> to accept ([y]es) the completion.
        --    This will auto-import if your LSP supports it.
        --    This will expand snippets if the LSP sent a snippet.
        -- 'super-tab' for tab to accept
        -- 'enter' for enter to accept
        -- 'none' for no mappings
        --
        -- For an understanding of why the 'default' preset is recommended,
        -- you will need to read `:help ins-completion`
        --
        -- No, but seriously. Please read `:help ins-completion`, it is really good!
        --
        -- All presets have the following mappings:
        -- <tab>/<s-tab>: move to right/left of your snippet expansion
        -- <c-space>: Open menu or open docs if already open
        -- <c-n>/<c-p> or <up>/<down>: Select next/previous item
        -- <c-e>: Hide menu
        -- <c-k>: Toggle signature help
        --
        -- See :h blink-cmp-config-keymap for defining your own keymap
        preset = 'default',

        -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
        --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
      },

      appearance = {
        -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
        -- Adjusts spacing to ensure icons are aligned
        nerd_font_variant = 'mono',
      },

      completion = {
        -- By default, you may press `<c-space>` to show the documentation.
        -- Optionally, set `auto_show = true` to show the documentation after a delay.
        documentation = { auto_show = false, auto_show_delay_ms = 500 },
      },

      sources = {
        default = { 'lsp', 'path', 'snippets', 'lazydev' },
        providers = {
          lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
        },
      },

      snippets = { preset = 'luasnip' },

      -- Blink.cmp includes an optional, recommended rust fuzzy matcher,
      -- which automatically downloads a prebuilt binary when enabled.
      --
      -- By default, we use the Lua implementation instead, but you may enable
      -- the rust implementation via `'prefer_rust_with_warning'`
      --
      -- See :h blink-cmp-config-fuzzy for more information
      fuzzy = { implementation = 'lua' },

      -- Shows a signature help window while you type arguments for a function
      signature = { enabled = true },
    },
  },

  -- { -- You can easily change to a different colorscheme.
  --   -- Change the name of the colorscheme plugin below, and then
  --   -- change the command in the config to whatever the name of that colorscheme is.
  --   --
  --   -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
  --   'folke/tokyonight.nvim',
  --   priority = 1000, -- Make sure to load this before all the other start plugins.
  --   config = function()
  --     ---@diagnostic disable-next-line: missing-fields
  --     require('tokyonight').setup {
  --       styles = {
  --         comments = { italic = true },
  --         keywords = { italic = true },
  --         functions = { bold = true },
  --       },
  --     }
  --
  --     -- Load the colorscheme here.
  --     -- Like many other themes, this one has different styles, and you could load
  --     -- any other, such as 'tokyonight-storm', 'tokyonight-moon', or 'tokyonight-day'.
  --     vim.cmd.colorscheme 'tokyonight-storm'
  --   end,
  -- },
  {
    'olimorris/onedarkpro.nvim',
    priority = 1000,
    config = function()
      require('onedarkpro').setup {
        highlights = {
          ['@lsp.typemod.variable.readonly.typescript'] = { fg = '#f0d090' },
          -- ['@type'] = { fg = '#f5e6b8' },
          ['@type.builtin'] = { fg = '#e0a070' },
          -- ['@type'] = { fg = '#fde68a', style = 'italic' }, -- Light gold
          ['@type'] = { fg = '#d8b4fe', style = 'italic' }, -- Light purple
          -- ['@type'] = { fg = '#7dd3fc' },
          -- ['@lsp.type.class'] = { fg = '#d8b4fe', style = 'italic' }, -- Light purple
          ['@lsp.typemod.variable.readonly.typescriptreact'] = { fg = '#e0de84' }, -- 25% lighter

          -- light blue arrow func
          ['@lsp.typemod.function.declaration.typescript'] = { fg = '#7dd3fc' },
          ['@lsp.typemod.function.readonly.typescript'] = { fg = '#7dd3fc' },

          -- python type hints
          ['@lsp.type.namespace.python'] = { fg = '#f0d090', style = 'italic' },
          ['@lsp.type.class.python'] = { fg = '#f0d090', style = 'italic' },
          Type = { fg = '#d19a66' },
        },

        styles = {
          functions = 'bold',
          comments = 'italic',
          variables = 'NONE',
          types = 'NONE',
        },
      }
      vim.cmd 'colorscheme onedark'
    end,
  },
  -- Highlight todo, notes, etc in comments
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },

  { -- Collection of various small independent plugins/modules
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
  },
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs', -- Sets main module to use for opts
    -- [[ Configure Treesitter ]] See `:help nvim-treesitter`
    opts = {
      ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
      -- Autoinstall languages that are not installed
      auto_install = true,
      highlight = {
        enable = true,
        -- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
        --  If you are experiencing weird indenting issues, add the language to
        --  the list of additional_vim_regex_highlighting and disabled languages for indent.
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = { enable = true, disable = { 'ruby' } },
    },
    -- There are additional nvim-treesitter modules that you can use to interact
    -- with nvim-treesitter. You should go explore a few and see what interests you:
    --
    --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
    --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
    --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
  },

  { -- Highlight, edit, and navigate code
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
  },

  -- https://github.com/nicbytes/nvim/commit/a6022c8cc1166f4a87315b3c2199476101239b8b#diff-198b05cba517df75101c39ad19ff87fed6db322ea83a1af861c2ae7105b3ba4bR200
  -- for rust formatting in lldb

  {
    'mrcjkb/rustaceanvim',
    version = '^5',
    lazy = false,
    config = function()
      vim.g.rustaceanvim = {
        dap = {
          load_rust_types = true,
        },
      }
    end,
  },
  -- Debug setup
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'jbyuki/one-small-step-for-vimkind',
      'nvim-neotest/nvim-nio',
      { 'theHamsta/nvim-dap-virtual-text', opts = {} },
      {
        'mfussenegger/nvim-dap-python',
        config = function()
          require('dap-python').setup 'python3'

          local dap = require 'dap'

          table.insert(dap.configurations.python, {
            name = 'Docker: Airflow Worker',
            type = 'python',
            request = 'attach',
            connect = {
              port = 5679,
              host = 'localhost',
            },
            pathMappings = {
              {
                localRoot = vim.fn.getcwd(),
                remoteRoot = '/opt/airflow',
              },
            },
            justMyCode = false,
            showReturnValue = true,
          })

          -- For attaching
          vim.defer_fn(function()
            print('Adapter type after setup:', type(dap.adapters.python))
            if type(dap.adapters.python) ~= 'function' then
              dap.adapters.python = function(cb, config)
                if config.request == 'attach' then
                  local port = (config.connect or config).port
                  local host = (config.connect or config).host or '127.0.0.1'
                  print('Connecting to ' .. host .. ':' .. port)
                  cb {
                    type = 'server',
                    port = port,
                    host = host,
                    options = { source_filetype = 'python' },
                  }
                else
                  cb {
                    type = 'executable',
                    command = '/Users/peterbull/.local/share/nvim/mason/bin/debugpy-adapter',
                    options = { source_filetype = 'python' },
                  }
                end
              end
            end
          end, 100)
        end,
        ft = 'python',
      },
      {
        'jay-babu/mason-nvim-dap.nvim',
        dependencies = 'mason.nvim',
        cmd = { 'DapInstall', 'DapUninstall' },
        opts = {
          automatic_installation = true,
          handlers = {},
          ensure_installed = {
            'js-debug-adapter',
            'codelldb',
          },
        },
      },
      {
        'mason-org/mason.nvim',
        opts = function(_, opts)
          opts.ensure_installed = opts.ensure_installed or {}
          vim.list_extend(opts.ensure_installed, {
            'js-debug-adapter',
            'codelldb',
          })
        end,
      },
    },
    keys = {
      {
        '<F5>',
        function()
          require('dap').continue()
        end,
        desc = 'Debug: Start/Continue',
      },
      {
        '<F11>',
        function()
          require('dap').step_into()
        end,
        desc = 'Debug: Step Into',
      },
      {
        '<F10>',
        function()
          require('dap').step_over()
        end,
        desc = 'Debug: Step Over',
      },
      {
        '<F9>',
        function()
          require('dap').step_out()
        end,
        desc = 'Debug: Step Out',
      },
      {
        '<F7>',
        function()
          require('dapui').toggle()
        end,
        desc = 'Debug: Toggle UI',
      },
      {
        '<leader>dB',
        function()
          require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
        end,
        desc = 'Breakpoint Condition',
      },
      {
        '<leader>db',
        function()
          require('dap').toggle_breakpoint()
        end,
        desc = 'Toggle Breakpoint',
      },
      {
        '<leader>dc',
        function()
          require('dap').continue()
        end,
        desc = 'Run/Continue',
      },
      {
        '<leader>dC',
        function()
          require('dap').run_to_cursor()
        end,
        desc = 'Run to Cursor',
      },
      {
        '<leader>dg',
        function()
          require('dap').goto_()
        end,
        desc = 'Go to Line (No Execute)',
      },
      {
        '<leader>di',
        function()
          require('dap').step_into()
        end,
        desc = 'Step Into',
      },
      {
        '<leader>dj',
        function()
          require('dap').down()
        end,
        desc = 'Down',
      },
      {
        '<leader>dk',
        function()
          require('dap').up()
        end,
        desc = 'Up',
      },
      {
        '<leader>dl',
        function()
          require('dap').run_last()
        end,
        desc = 'Run Last',
      },
      {
        '<leader>do',
        function()
          require('dap').step_out()
        end,
        desc = 'Step Out',
      },
      {
        '<leader>dO',
        function()
          require('dap').step_over()
        end,
        desc = 'Step Over',
      },
      {
        '<leader>dP',
        function()
          require('dap').pause()
        end,
        desc = 'Pause',
      },
      {
        '<leader>dr',
        function()
          require('dap').repl.toggle()
        end,
        desc = 'Toggle REPL',
      },
      {
        '<leader>ds',
        function()
          require('dap').session()
        end,
        desc = 'Session',
      },
      {
        '<leader>dt',
        function()
          require('dap').terminate()
        end,
        desc = 'Terminate',
      },
      {
        '<leader>dw',
        function()
          require('dap.ui.widgets').hover()
        end,
        desc = 'Widgets',
      },
      {
        '<leader>dL',
        function()
          require('dap.ext.vscode').load_launchjs()
        end,
        desc = 'Load launch.json',
      },
      {
        '<leader>da',
        function()
          vim.cmd 'DapNew Debug\\ pnpm\\ dev\\ (Node.js) Next.js:\\ debug\\ client-side Attach\\ to\\ Pipeline'
        end,
        desc = 'Launch compound',
      },
      {
        '<leader>dE',
        function()
          local dap = require 'dap'
          local breakpoints = require 'dap.breakpoints'

          if vim.g.dap_breakpoints_saved then
            -- Restore breakpoints
            for bufnr, buf_bps in pairs(vim.g.dap_breakpoints_saved) do
              for _, bp in pairs(buf_bps) do
                breakpoints.set({
                  condition = bp.condition,
                  hit_condition = bp.hitCondition,
                  log_message = bp.logMessage,
                }, bufnr, bp.line)
              end
            end
            vim.g.dap_breakpoints_saved = nil
            vim.notify('Breakpoints restored', vim.log.levels.INFO)
          else
            -- Save and clear breakpoints
            local bps = breakpoints.get()
            local has_breakpoints = false
            for _, buf_bps in pairs(bps) do
              if next(buf_bps) then
                has_breakpoints = true
                break
              end
            end

            if has_breakpoints then
              vim.g.dap_breakpoints_saved = vim.deepcopy(bps)
              dap.clear_breakpoints()
              vim.notify('Breakpoints cleared (saved)', vim.log.levels.INFO)
            else
              vim.notify('No breakpoints to clear', vim.log.levels.INFO)
            end
          end
        end,
        desc = 'Toggle Clear/Restore All Breakpoints',
      },
      {
        '<leader>dR',
        function()
          local dap = require 'dap'
          dap.clear_breakpoints()
          vim.g.dap_breakpoints_saved = nil
          vim.notify('All breakpoints permanently removed', vim.log.levels.INFO)
        end,
        desc = 'Remove All Breakpoints Permanently',
      },
    },
    config = function()
      local dap = require 'dap'

      -- Enable DAP logging for debugging issues
      dap.set_log_level 'INFO'

      -- Setup pwa-node adapter (JavaScript/TypeScript)
      dap.adapters['pwa-node'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = {
            vim.fn.stdpath 'data' .. '/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js',
            '${port}',
          },
        },
      }

      -- Setup node adapter (compatibility layer)
      dap.adapters['node'] = function(cb, config)
        if config.type == 'node' then
          config.type = 'pwa-node'
        end
        local nativeAdapter = dap.adapters['pwa-node']
        if type(nativeAdapter) == 'function' then
          nativeAdapter(cb, config)
        else
          cb(nativeAdapter)
        end
      end

      -- Setup Chrome adapter
      dap.adapters['pwa-chrome'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = {
            vim.fn.stdpath 'data' .. '/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js',
            '${port}',
          },
        },
      }

      -- Setup LLDB adapter for C/C++/Rust
      dap.adapters.lldb = {
        type = 'executable',
        command = vim.fn.stdpath 'data' .. '/mason/packages/codelldb/extension/adapter/codelldb',
        name = 'lldb',
      }

      -- Setup codelldb adapter (alternative name)
      dap.adapters.codelldb = dap.adapters.lldb

      -- Bash Debug Adapter Setup
      dap.adapters.sh = {
        type = 'executable',
        command = vim.fn.stdpath 'data' .. '/mason/bin/bash-debug-adapter',
        name = 'sh',
      }

      -- -- LUA
      -- dap.adapters['local-lua'] = {
      --   type = 'executable',
      --   command = 'node',
      --   args = {
      --     vim.fn.stdpath 'data' .. '/mason/packages/local-lua-debugger-vscode/extension/extension/debugAdapter.js',
      --   },
      --   enrich_config = function(config, on_config)
      --     if not config['extensionPath'] then
      --       local c = vim.deepcopy(config)
      --       c.extensionPath = vim.fn.stdpath 'data' .. '/mason/packages/local-lua-debugger-vscode/extension/'
      --       on_config(c)
      --     else
      --       on_config(config)
      --     end
      --   end,
      -- }
      -- dap.configurations.lua = {
      --   {
      --     name = 'Current file (local-lua-dbg, nlua)',
      --     type = 'local-lua',
      --     request = 'launch',
      --     cwd = '${workspaceFolder}',
      --     program = {
      --       lua = 'nlua.lua',
      --       file = '${file}',
      --     },
      --     verbose = true,
      --     args = {},
      --   },
      -- }

      dap.configurations.lua = {
        {
          type = 'nlua',
          request = 'attach',
          name = 'Attach to running Neovim instance',
        },
      }
      dap.adapters.nlua = function(callback, config)
        callback { type = 'server', host = config.host or '127.0.0.1', port = config.port or 8086 }
      end
      vim.keymap.set('n', '<leader>dN', function()
        require('osv').launch { port = 8086 }
      end, { noremap = true, desc = 'Launch [N]vim Debug Server' })
      vim.keymap.set('n', '<leader>dw', function()
        local widgets = require 'dap.ui.widgets'
        widgets.hover()
      end, { noremap = true, desc = 'Hover [W]idget' })

      local js_filetypes = { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' }

      -- Setup vscode compatibility
      local vscode = require 'dap.ext.vscode'
      vscode.type_to_filetypes['node'] = js_filetypes
      vscode.type_to_filetypes['pwa-node'] = js_filetypes
      vscode.type_to_filetypes['pwa-chrome'] = js_filetypes
      vscode.type_to_filetypes['lldb'] = { 'c', 'cpp', 'rust', 'zig' }
      vscode.type_to_filetypes['codelldb'] = { 'c', 'cpp', 'rust', 'zig' }
      vscode.type_to_filetypes['sh'] = { 'sh', 'bash' }
      -- Setup JavaScript/TypeScript configurations
      for _, language in ipairs(js_filetypes) do
        dap.configurations[language] = {
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Launch Current Node File(File Dir)',
            program = '${file}',
            cwd = '${fileDirName}',
            console = 'integratedTerminal',
          },
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Launch Current Node File (Project Dir with args)',
            program = '${file}',
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            args = function()
              local args_str = vim.fn.input 'Arguments: '
              return vim.split(args_str, ' ')
            end,
          },
          {
            type = 'pwa-node',
            request = 'attach',
            name = 'Attach',
            processId = require('dap.utils').pick_process,
            cwd = '${workspaceFolder}',
          },
        }
      end

      local function get_rust_package_name()
        local cargo_toml_path = vim.fn.getcwd() .. '/Cargo.toml'

        if vim.fn.filereadable(cargo_toml_path) == 1 then
          local cargo_content = vim.fn.readfile(cargo_toml_path)

          for _, line in ipairs(cargo_content) do
            local name = line:match '^name%s*=%s*"([^"]+)"'
            if name then
              return name
            end
          end
        end

        return nil
      end

      -- C/Rust config
      dap.configurations.c = {
        {
          name = 'Launch C Default',
          type = 'lldb',
          request = 'launch',
          program = function()
            local extension = vim.fn.expand '%:e'
            if extension == 'c' then
              local result = vim.fn.system 'make'
              if vim.v.shell_error ~= 0 then
                vim.notify('Build failed: ' .. result, vim.log.levels.ERROR)
                return nil
              end
              local exe_path = vim.fn.getcwd() .. '/build/main'

              vim.fn.system('chmod +x ' .. exe_path)
              return exe_path
            end
            if extension == 'rs' then
              local result = vim.fn.system 'cargo build'
              if vim.v.shell_error ~= 0 then
                vim.notify('Build failed: ' .. result, vim.log.levels.ERROR)
                return nil
              end
            end
            local package_name = get_rust_package_name() or 'backend'
            local exe_path = vim.fn.getcwd() .. '/target/debug/' .. package_name
            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
      }

      dap.configurations.rust = {
        {
          name = 'Launch Rust Workspace',
          type = 'lldb',
          request = 'launch',
          program = function()
            local result = vim.fn.system 'cargo build'
            if vim.v.shell_error ~= 0 then
              vim.notify('Cargo build failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            local package_name = get_rust_package_name() or 'backend'
            local exe_path = vim.fn.getcwd() .. '/target/debug/' .. package_name
            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
        {
          name = 'Launch Rust Current File',
          type = 'lldb',
          request = 'launch',
          program = function()
            local current_file = vim.fn.expand '%:p'
            local file_name = vim.fn.expand '%:t:r'
            local exe_path = vim.fn.getcwd() .. '/target/debug/' .. file_name

            vim.fn.system('mkdir -p ' .. vim.fn.getcwd() .. '/target/debug')

            local compile_cmd = string.format('rustc -g --edition 2021 -o %s %s', exe_path, current_file)
            local result = vim.fn.system(compile_cmd)

            if vim.v.shell_error ~= 0 then
              vim.notify('Rust compile failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
      }

      dap.configurations.zig = {
        {
          name = 'Launch Zig Workspace',
          type = 'lldb',
          request = 'launch',
          program = function()
            local result = vim.fn.system 'zig build'
            if vim.v.shell_error ~= 0 then
              vim.notify('Zig build failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            local exe_path = vim.fn.getcwd() .. '/zig-out/bin/'
            local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
            -- zig renames with underscore on build
            project_name = string.gsub(project_name, '-', '_')
            exe_path = exe_path .. project_name

            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
          initCommands = {
            'type format add --format decimal uint8_t',
            'type format add --format decimal "unsigned char"',
          },
        },
        {
          name = 'Launch Zig Current File',
          type = 'lldb',
          request = 'launch',
          program = function()
            local current_file = vim.fn.expand '%:p'
            local file_name = vim.fn.expand '%:t:r'
            local exe_path = vim.fn.getcwd() .. '/zig-out/bin/' .. file_name

            vim.fn.system('mkdir -p ' .. vim.fn.getcwd() .. '/zig-out/bin')

            local compile_cmd = string.format('zig build-exe -femit-bin=%s %s', exe_path, current_file)
            local result = vim.fn.system(compile_cmd)

            if vim.v.shell_error ~= 0 then
              vim.notify('Zig compile failed: ' .. result, vim.log.levels.ERROR)
              return nil
            end

            return exe_path
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
          initCommands = {
            'type format add --format decimal uint8_t',
            'type format add --format decimal "unsigned char"',
          },
        },
      }
      dap.configurations.cpp = dap.configurations.c
      dap.configurations.sh = {
        {
          name = 'Launch Bash debugger',
          type = 'sh',
          request = 'launch',
          program = '${file}',
          cwd = '${fileDirname}',
          pathBashdb = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb',
          pathBashdbLib = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir',
          pathBash = 'bash',
          pathCat = 'cat',
          pathMkfifo = 'mkfifo',
          pathPkill = 'pkill',
          env = {},
          args = {},
          stopOnEntry = false,
        },
        {
          name = 'Launch Bash Script with Args',
          type = 'sh',
          request = 'launch',
          program = '${file}',
          cwd = '${fileDirname}',
          pathBashdb = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb',
          pathBashdbLib = vim.fn.stdpath 'data' .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir',
          pathBash = 'bash',
          pathCat = 'cat',
          pathMkfifo = 'mkfifo',
          pathPkill = 'pkill',
          env = {},
          stopOnEntry = false,
          args = function()
            local args_str = vim.fn.input 'Arguments: '
            return vim.split(args_str, ' ')
          end,
        },
      }

      -- Also support .bash files
      dap.configurations.bash = dap.configurations.sh

      -- Also support .bash files
      dap.configurations.bash = dap.configurations.sh

      -- dap.configurations.lua = {
      --   {
      --     name = 'Current file (local-lua-dbg, lua)',
      --     type = 'nlua',
      --     request = 'launch',
      --     cwd = '${workspaceFolder}',
      --     program = {
      --       lua = 'nlua',
      --       file = '${file}',
      --     },
      --     args = {},
      --     verbose = true,
      --   },
      -- }

      -- Auto-load launch.json when entering a directory
      vim.api.nvim_create_autocmd('DirChanged', {
        callback = function()
          local launch_json = vim.fn.getcwd() .. '/.vscode/launch.json'
          if vim.fn.filereadable(launch_json) == 1 then
            require('dap.ext.vscode').load_launchjs(launch_json, {
              ['pwa-node'] = js_filetypes,
              ['pwa-chrome'] = js_filetypes,
              ['node'] = js_filetypes,
              ['chrome'] = js_filetypes,
              ['lldb'] = { 'c', 'cpp', 'rust' },
              ['codelldb'] = { 'c', 'cpp', 'rust' },
              ['sh'] = { 'sh', 'bash' },
            })
            print('Auto-loaded: ' .. launch_json)
          end
        end,
      })

      -- Also load launch.json on startup if it exists
      local startup_launch_json = vim.fn.getcwd() .. '/.vscode/launch.json'
      if vim.fn.filereadable(startup_launch_json) == 1 then
        require('dap.ext.vscode').load_launchjs(startup_launch_json, {
          ['pwa-node'] = js_filetypes,
          ['pwa-chrome'] = js_filetypes,
          ['node'] = js_filetypes,
          ['chrome'] = js_filetypes,
          ['lldb'] = { 'c', 'cpp', 'rust' },
          ['codelldb'] = { 'c', 'cpp', 'rust' },
          ['bashdb'] = { 'sh', 'bash' },
          ['sh'] = { 'sh', 'bash' },
        })
      end

      -- Set up highlights
      vim.api.nvim_set_hl(0, 'DapStoppedLine', { default = true, link = 'Visual' })

      -- Set up DAP signs
      local dap_icons = {
        Stopped = { '󰁕 ', 'DiagnosticWarn', 'DapStoppedLine' },
        Breakpoint = ' ',
        BreakpointCondition = ' ',
        BreakpointRejected = { ' ', 'DiagnosticError' },
        LogPoint = '.>',
      }

      for name, sign in pairs(dap_icons) do
        vim.fn.sign_define('Dap' .. name, {
          text = sign[1],
          texthl = sign[2] or 'DiagnosticInfo',
          linehl = sign[3],
          numhl = sign[3],
        })
      end

      vim.api.nvim_create_user_command('DapStatus', function()
        print('DAP adapters:', vim.inspect(vim.tbl_keys(dap.adapters)))
        if dap.get_log_file_path then
          print('DAP log file:', dap.get_log_file_path())
        end
        local js_configs = dap.configurations.javascript or {}
        print('JavaScript configs:', #js_configs)
        local c_configs = dap.configurations.c or {}
        print('C configs:', #c_configs)
      end, { desc = 'Show DAP status' })
    end,
  },
  {
    'jonathan-elize/dap-info.nvim',
    dependencies = {
      'mfussenegger/nvim-dap',
    },
    config = function()
      require('dap-info').setup {}
    end,
  },

  -- fancy UI for the debugger
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'nvim-neotest/nvim-nio' },
    keys = {
      {
        '<leader>du',
        function()
          require('dapui').toggle {}
        end,
        desc = 'Dap UI',
      },
      {
        '<leader>dU',
        function()
          local dapui = require 'dapui'
          dapui.close()
          dapui.open { reset = true }
        end,
        desc = 'Reset Dap UI',
      },
      {
        '<leader>de',
        function()
          require('dapui').eval()
        end,
        desc = 'Eval',
        mode = { 'n', 'v' },
      },
    },
    opts = {},
    config = function(_, opts)
      local dap = require 'dap'
      local dapui = require 'dapui'
      dapui.setup(opts)
      dap.listeners.after.event_initialized['dapui_config'] = function()
        -- dapui.open {}
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        -- dapui.close {}
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        -- dapui.close {}
      end
    end,
  },
  {
    -- Lua
    {
      'folke/persistence.nvim',
      event = 'BufReadPre', -- this will only start session saving when an actual file was opened
      opts = {
        -- add any custom options here
      },
      keys = {
        {
          '<leader>qs',
          function()
            require('persistence').load()
          end,
          desc = 'Load session for current dir',
        },
        {
          '<leader>qS',
          function()
            require('persistence').select()
          end,
          desc = 'Select session to load',
        },
        {
          '<leader>ql',
          function()
            require('persistence').load { last = true }
          end,
          desc = 'Load last session',
        },
        {
          '<leader>qd',
          function()
            require('persistence').stop()
          end,
          desc = 'Stop session saving',
        },
      },
    },
  },

  {
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

      -- Simple keymap to toggle terminal
      vim.keymap.set('n', '<leader>tt', '<cmd>ToggleTerm direction=vertical<CR>', { desc = 'Toggle Terminal (Right)' })
      vim.keymap.set('t', '<leader>tt', '<cmd>ToggleTerm<CR>', { desc = 'Toggle Terminal (Right)' })

      -- Optional: Add a horizontal terminal toggle too
      vim.keymap.set('n', '<leader>th', '<cmd>ToggleTerm direction=horizontal<CR>', { desc = 'Toggle Terminal (Bottom)' })
    end,
  },

  -- Fugitive plugin
  {
    'tpope/vim-fugitive',
    cmd = { 'Git', 'G', 'Gdiffsplit', 'Gread', 'Gwrite', 'Ggrep', 'GMove', 'GDelete', 'GBrowse' },
    keys = {
      -- Git status (like lazygit's main view)
      { '<leader>gs', '<cmd>Git<CR>', desc = 'Git Status' },

      -- Git log
      { '<leader>gl', '<cmd>Git log --oneline<CR>', desc = 'Git Log' },

      -- Git add current file
      { '<leader>ga', '<cmd>Gwrite<CR>', desc = 'Git Add Current File' },

      -- Git commit
      { '<leader>gc', '<cmd>Git commit<CR>', desc = 'Git Commit' },

      -- Git push
      { '<leader>gp', '<cmd>Git push<CR>', desc = 'Git Push' },

      -- Git pull
      { '<leader>gP', '<cmd>Git pull<CR>', desc = 'Git Pull' },
    },
  },

  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory' },
    keys = {
      {
        '<leader>gd',
        function()
          require 'diffview'
          local lib = require 'diffview.lib'

          if next(lib.views) == nil then
            vim.cmd 'DiffviewOpen'
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = 'Current file changes (staged/unstaged)',
      },
      {
        '<leader>gm',
        function()
          require 'diffview'
          local lib = require 'diffview.lib'

          if next(lib.views) == nil then
            vim.cmd 'DiffviewOpen'
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = 'Diff vs previous commit',
      },

      {
        '<leader>gM',
        function()
          require 'diffview'
          local lib = require 'diffview.lib'

          -- Get current branch name
          local current_branch = vim.fn.system('git branch --show-current'):gsub('\n', '')

          -- Function to get the default branch (main or master)
          local function get_default_branch()
            -- Try to get the default branch from remote
            local default_branch = vim.fn.system('git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null'):gsub('refs/remotes/origin/', ''):gsub('\n', '')

            -- If that fails, check if main or master exists
            if default_branch == '' then
              local main_exists = vim.fn.system 'git show-ref --verify --quiet refs/heads/main 2>/dev/null'
              if vim.v.shell_error == 0 then
                default_branch = 'main'
              else
                local master_exists = vim.fn.system 'git show-ref --verify --quiet refs/heads/master 2>/dev/null'
                if vim.v.shell_error == 0 then
                  default_branch = 'master'
                else
                  default_branch = 'main' -- fallback
                end
              end
            end

            return default_branch
          end

          local default_branch = get_default_branch()
          local cmd

          if current_branch == default_branch then
            -- On default branch: show only working tree changes
            cmd = 'DiffviewOpen'
          else
            -- On feature branch: show all changes since default branch INCLUDING working tree
            cmd = 'DiffviewOpen ' .. default_branch
          end

          if next(lib.views) == nil then
            vim.cmd(cmd)
          else
            vim.cmd 'DiffviewClose'
          end
        end,
      },

      config = function()
        require('diffview').setup {
          use_icons = vim.g.have_nerd_font,
          view = {
            default = {
              layout = 'diff2_horizontal',
            },
          },
          keymap = {
            view = {
              -- Reset hunk in diffview
              ['<leader>grh'] = function()
                vim.cmd 'DiffviewClose'
                -- Switch to the actual file and reset hunk
                vim.schedule(function()
                  require('gitsigns').reset_hunk()
                end)
              end,
            },
          },
        }
      end,
    },
  },

  {
    'folke/trouble.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {},
    cmd = 'Trouble',
    keys = {
      {
        '<leader>xx',
        '<cmd>Trouble diagnostics toggle<cr>',
        desc = 'Diagnostics (Trouble)',
      },
      {
        '<leader>xX',
        '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
        desc = 'Buffer Diagnostics (Trouble)',
      },
      {
        '<leader>cs',
        '<cmd>Trouble symbols toggle focus=false<cr>',
        desc = 'Symbols (Trouble)',
      },
      {
        '<leader>cl',
        '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
        desc = 'LSP Definitions / references / ... (Trouble)',
      },
      {
        '<leader>xL',
        '<cmd>Trouble loclist toggle<cr>',
        desc = 'Location List (Trouble)',
      },
      {
        '<leader>xQ',
        '<cmd>Trouble qflist toggle<cr>',
        desc = 'Quickfix List (Trouble)',
      },
    },
  },
  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local harpoon = require 'harpoon'
      harpoon:setup {}

      -- basic telescope configuration
      local conf = require('telescope.config').values
      local function toggle_telescope(harpoon_files)
        local file_paths = {}
        for _, item in ipairs(harpoon_files.items) do
          table.insert(file_paths, item.value)
        end

        require('telescope.pickers')
          .new({}, {
            prompt_title = 'Harpoon',
            finder = require('telescope.finders').new_table {
              results = file_paths,
            },
            previewer = conf.file_previewer {},
            sorter = conf.generic_sorter {},
          })
          :find()
      end

      vim.keymap.set('n', '<C-e>', function()
        toggle_telescope(harpoon:list())
      end, { desc = 'Open harpoon window' })
      vim.keymap.set('n', '<leader>ha', function()
        harpoon:list():add()
      end, { desc = '[A]dd to harpoon' })
      vim.keymap.set('n', '<C-S-P>', function()
        harpoon:list():prev()
      end)
      vim.keymap.set('n', '<C-S-N>', function()
        harpoon:list():next()
      end)
      vim.keymap.set('n', '<leader>hc', function()
        harpoon:list():clear()
      end, { desc = '[C]lear harpoon' })
    end,
  },
  {
    'linux-cultist/venv-selector.nvim',
    dependencies = {
      'neovim/nvim-lspconfig',
      { 'nvim-telescope/telescope.nvim', branch = '0.1.x', dependencies = { 'nvim-lua/plenary.nvim' } }, -- optional: you can also use fzf-lua, snacks, mini-pick instead.
    },
    ft = 'python', -- Load when opening Python files
    keys = {
      -- { ',v', '<cmd>VenvSelect<cr>' }, -- Open picker on keymap
    },
    opts = { -- this can be an empty lua table - just showing below for clarity.
      search = {}, -- if you add your own searches, they go here.
      options = {}, -- if you add plugin options, they go here.
    },
  },
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    build = 'cd app && yarn install',
    init = function()
      vim.g.mkdp_filetypes = { 'markdown' }
    end,
    ft = { 'markdown' },
  },
  {
    '3rd/image.nvim',
    opts = {
      backend = 'kitty', -- or "ueberzug" or "sixel"
      processor = 'magick_cli', -- or "magick_rock"
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
          only_render_image_at_cursor_mode = 'popup', -- or "inline"
          floating_windows = false, -- if true, images will be rendered in floating markdown windows
          filetypes = { 'markdown', 'vimwiki' }, -- markdown extensions (ie. quarto) can go here
        },
        neorg = {
          enabled = true,
          filetypes = { 'norg' },
        },
        typst = {
          enabled = true,
          filetypes = { 'typst' },
        },
        html = {
          enabled = false,
        },
        css = {
          enabled = false,
        },
      },

      scale_factor = 1.0,
      max_width = 100, -- tweak to preference
      max_height = 12, -- ^
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
      window_overlap_clear_enabled = true, -- toggles images when windows are overlapped
      window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', 'snacks_notif', 'scrollview', 'scrollview_sign' },
      editor_only_render_when_focused = false, -- auto show/hide images when the editor gains/looses focus
      tmux_show_only_in_active_window = false, -- auto show/hide images in the correct Tmux window (needs visual-activity off)
      hijack_file_patterns = { '*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.avif' }, -- render image files as images when opened
    },
  },
  {
    'benlubas/molten-nvim',
    version = '^1.0.0', -- use version <2.0.0 to avoid breaking changes
    dependencies = { '3rd/image.nvim' },
    build = ':UpdateRemotePlugins',
    init = function()
      -- these are examples, not defaults. Please see the readme
      vim.g.molten_image_provider = 'image.nvim'
      vim.g.molten_output_win_max_height = 20
    end,
    config = function()
      -- Keybindings for Molten
      vim.keymap.set('n', '<leader>mi', ':MoltenInit python3<CR>', { desc = 'Initialize Molten' })
      vim.keymap.set('n', '<leader>ml', ':MoltenEvaluateLine<CR>', { desc = 'Evaluate line' })
      vim.keymap.set('v', '<leader>me', ':<C-u>MoltenEvaluateVisual<CR>gv', { desc = 'Evaluate visual selection' })
      vim.keymap.set('n', '<leader>mc', ':MoltenReevaluateCell<CR>', { desc = 'Re-evaluate cell' })
      vim.keymap.set('n', '<leader>mo', ':MoltenShowOutput<CR>', { desc = 'Show output' })
      vim.keymap.set('n', '<leader>mh', ':MoltenHideOutput<CR>', { desc = 'Hide output' })
      vim.keymap.set('n', '<leader>md', ':MoltenDelete<CR>', { desc = 'Delete cell output' })
      vim.keymap.set('n', '<leader>mn', ':MoltenNext<CR>', { desc = 'Next cell' })
      vim.keymap.set('n', '<leader>mp', ':MoltenPrev<CR>', { desc = 'Previous cell' })
      vim.keymap.set('n', '<leader>mq', ':MoltenDeinit<CR>', { desc = 'Quit Molten' })
      vim.keymap.set('n', '<leader>mR', ':MoltenRestart<CR>', { desc = 'Restart Molten' })
      vim.keymap.set('n', '<leader>ma', ':MoltenEvaluateOperator<CR>gg0VG', { desc = 'Run all cells' })
      vim.keymap.set('n', '<leader>mx', ':MoltenHideOutput<CR>:MoltenDelete<CR>', { desc = 'Clear all outputs' })
    end,
  },
  {
    'uga-rosa/ccc.nvim',
    cmd = { 'CccPick', 'CccConvert', 'CccHighlighterToggle' },
    keys = {
      { '<leader>cp', '<cmd>CccPick<cr>', desc = 'Color picker' },
      { '<leader>cc', '<cmd>CccConvert<cr>', desc = 'Convert color' },
      { '<leader>ct', '<cmd>CccHighlighterToggle<cr>', desc = 'Toggle highlighter' },
    },
    config = function()
      local ccc = require 'ccc'
      ccc.setup {
        highlighter = {
          auto_enable = true,
          lsp = true,
          excludes = { 'lazy', 'mason', 'help', 'neo-tree' },
        },
        pickers = {
          ccc.picker.hex,
          ccc.picker.css_rgb,
          ccc.picker.css_hsl,
          ccc.picker.css_hwb,
        },
        alpha_show = 'auto',
        recognize = { input = true, output = true },
        inputs = { ccc.input.rgb, ccc.input.hsl, ccc.input.cmyk },
        outputs = {
          ccc.output.hex,
          ccc.output.css_rgb,
          ccc.output.css_hsl,
        },
      }
    end,
  },

  {
    'Vigemus/iron.nvim',
    config = function()
      local iron = require 'iron.core'
      local view = require 'iron.view'
      local common = require 'iron.fts.common'
      --
      -- Test debug function
      local function debug_test()
        print 'DEBUG: Test function called!'
        local test_var = 'Hello from debug test'
        print('DEBUG: test_var =', test_var)
        -- This is where you'll set your breakpoint
        local another_var = 42
        print('DEBUG: another_var =', another_var)
        return test_var, another_var
      end

      iron.setup {
        config = {
          -- Whether a repl should be discarded or not
          scratch_repl = true,
          -- Your repl definitions come here
          repl_definition = {
            sh = {
              command = { 'zsh' },
            },
            python = {
              command = { 'python3' }, -- or { "ipython", "--no-autoindent" }
              format = common.bracketed_paste_python,
              block_dividers = { '# %%', '#%%' },
              env = { PYTHON_BASIC_REPL = '1' }, --this is needed for python3.13 and up.
            },

            javascript = {
              command = {
                'deno',
                'repl',
                '--allow-all',
                '--unstable-node-globals',
                '--unstable-byonm',
                '--unstable-ffi',
                '--unstable-bare-node-builtins',
              },
            },
            typescript = {
              command = {
                'deno',
                'repl',
                '--allow-all',
                '--unstable-node-globals',
                '--unstable-byonm',
                '--unstable-ffi',
                '--unstable-bare-node-builtins',
              },
            },
            rust = {
              command = { 'evcxr' },
            },
          },
          -- How the repl window will be displayed
          repl_open_cmd = view.split.vertical.rightbelow(0.4), -- 40% width on the right

          -- Set the file type of the newly created repl
          repl_filetype = function(bufnr, ft)
            return ft
          end,

          -- Send selections to the DAP repl if an nvim-dap session is running
          dap_integration = true,
        },

        keymaps = {
          toggle_repl = '<space>rr', -- Toggle REPL
          restart_repl = '<space>rR', -- Restart REPL
          send_motion = '<space>rc', -- Send motion (was <space>sc)
          visual_send = '<space>rc', -- Send visual selection (was <space>sc)
          send_file = '<space>rF', -- Send entire file (was <space>sf)
          send_line = '<space>rl', -- Send current line (was <space>sl)
          send_paragraph = '<space>rp', -- Send paragraph (was <space>sp)
          send_until_cursor = '<space>ru', -- Send until cursor (was <space>su)
          send_mark = '<space>rm', -- Send mark (was <space>sm)
          send_code_block = '<space>rb', -- Send code block (was <space>sb)
          send_code_block_and_move = '<space>rn', -- Send code block and move (was <space>sn)
          mark_motion = '<space>rmc', -- Mark motion (was <space>mc)
          mark_visual = '<space>rmc', -- Mark visual (was <space>mc)
          remove_mark = '<space>rmd', -- Remove mark (was <space>md)
          cr = '<space>r<cr>', -- Send carriage return (was <space>s<cr>)
          interrupt = '<space>ri', -- Interrupt (was <space>s<space>)
          exit = '<space>rq', -- Exit REPL (was <space>sq)
          clear = '<space>rcl', -- Clear REPL (was <space>cl)
        },

        -- Highlight settings
        highlight = {
          italic = true,
        },
        ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
      }

      -- Additional keymaps
      vim.keymap.set('n', '<space>rf', '<cmd>IronFocus<cr>', { desc = 'Focus REPL' })
      vim.keymap.set('n', '<space>rh', '<cmd>IronHide<cr>', { desc = 'Hide REPL' })
      vim.keymap.set('n', '<space>rt', function()
        print 'DEBUG: Test keymap pressed!'
        debug_test()
      end, { desc = 'Debug Test Function' })
    end,
  },

  {
    'cenk1cenk2/schema-companion.nvim',
    dependencies = {
      { 'nvim-lua/plenary.nvim' },
    },
    config = function()
      require('schema-companion').setup {
        log_level = vim.log.levels.INFO,
      }
    end,
  },
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = true,
    -- use opts = {} for passing setup options
    -- this is equivalent to setup({}) function
  },
  -- {
  --   'catgoose/nvim-colorizer.lua',
  --   event = 'VeryLazy',
  --   opts = {
  --     lazy_load = true,
  --     filetypes = {
  --       'css',
  --       'javascriptreact',
  --       'typescriptreact',
  --     },
  --   },
  -- },
  -- {
  --   'piersolenski/import.nvim',
  --   dependencies = {
  --     -- One of the following pickers is required:
  --     'nvim-telescope/telescope.nvim',
  --     -- 'folke/snacks.nvim',
  --     -- 'ibhagwan/fzf-lua',
  --   },
  --   opts = {
  --     picker = 'telescope',
  --   },
  --   keys = {
  --     {
  --       '<leader>si',
  --       function()
  --         require('import').pick()
  --       end,
  --       desc = '[S]earch [I]mports',
  --     },
  --   },
  -- },

  -- The following comments only work if you have downloaded the kickstart repo, not just copy pasted the
  -- init.lua. If you want these files, they are in the repository, so you can just download them and
  -- place them in the correct locations.

  -- NOTE: Next step on your Neovim journey: Add/Configure additional plugins for Kickstart
  --
  --  Here are some example plugins that I've included in the Kickstart repository.
  --  Uncomment any of the lines below to enable them (you will need to restart nvim).
  --
  -- require 'kickstart.plugins.debug',
  -- require 'kickstart.plugins.indent_line',
  -- require 'kickstart.plugins.lint',
  -- require 'kickstart.plugins.autopairs',
  -- require 'kickstart.plugins.neo-tree',
  -- require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps

  -- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
  --    This is the easiest way to modularize your config.
  --
  --  Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
  -- { import = 'custom.plugins' },
  --
  -- For additional information with loading, sourcing and examples see `:help lazy.nvim-🔌-plugin-spec`
  -- Or use telescope!
  -- In normal mode type `<space>sh` then write `lazy.nvim-plugin`
  -- you can continue same window with `<space>sr` which resumes last telescope search
}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})
vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = { '*.env', '.env*' },
  callback = function()
    -- Disable all diagnostics for this buffer
    vim.diagnostic.enable(false)
  end,
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
