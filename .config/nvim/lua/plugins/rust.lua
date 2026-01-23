-- https://github.com/nicbytes/nvim/commit/a6022c8cc1166f4a87315b3c2199476101239b8b#diff-198b05cba517df75101c39ad19ff87fed6db322ea83a1af861c2ae7105b3ba4bR200
-- for rust formatting in lldb
return {
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
  -- {
  --   'cordx56/rustowl',
  --   version = '*', -- Latest stable version
  --   build = 'cargo binstall rustowl',
  --   lazy = false, -- This plugin is already lazy
  --   opts = {
  --     auto_enable = true,
  --     highlight_style = 'underline',
  --     client = {
  --       on_attach = function(_, buffer)
  --         vim.keymap.set('n', '<leader>o', function()
  --           require('rustowl').toggle(buffer)
  --         end, { buffer = buffer, desc = 'Toggle RustOwl' })
  --       end,
  --     },
  --   },
  -- },
}
