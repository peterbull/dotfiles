-- Sorbet RBI files are plain Ruby syntax. Mapping them to the ruby filetype is what pulls in
-- the ruby ftplugin, the treesitter ruby parser, and both ruby_lsp and sorbet (each lists
-- 'ruby' in its `filetypes`), so nothing in lsp.lua/treesitter.lua needs an extra filetype.
vim.filetype.add {
  extension = {
    rbi = 'ruby',
  },
}
