return {
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
}
