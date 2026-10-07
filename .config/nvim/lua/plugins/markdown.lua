return {
  {
    'OXY2DEV/markview.nvim',
    lazy = false, -- already lazy-loaded internally, don't lazy-load
    dependencies = {
      'saghen/blink.cmp', -- callout/checkbox completions
    },
    config = function()
      require('markview').setup()
    end,
  },
  {
    'kais-radwan/ascii-mermaid',
    ft = 'markdown',
    opts = {},
  },
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreview', 'MarkdownPreviewToggle', 'MarkdownPreviewStop' },
    ft = { 'markdown' },
    -- Corepack needs no global pnpm shim; optional native dependency scripts stay blocked.
    build = 'cd app && MISE_AUTO_INSTALL=0 COREPACK_ENABLE_AUTO_PIN=0 COREPACK_ENABLE_PROJECT_SPEC=0 COREPACK_DEFAULT_TO_LATEST=0 mise --no-config exec node@24 -- corepack pnpm@12.3.4 install --ignore-scripts --config.minimumReleaseAge=10080 --config.minimumReleaseAgeStrict=true --config.minimumReleaseAgeIgnoreMissingTime=false',
    keys = {
      { '<leader>lp', '<cmd>MarkdownPreviewToggle<CR>', desc = '[l]ive [p]review markdown in browser' },
      { '<leader>lP', '<cmd>MarkdownPreviewStop<CR>', desc = '[l]ive [P]review markdown (close)' },
    },
    -- vim.g.mkdp_* must be set before the plugin loads (no setup() call)
    init = function()
      vim.g.mkdp_filetypes = { 'markdown' }
      vim.g.mkdp_theme = 'dark' -- matches onedarkpro
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1 -- close preview when the buffer closes
      vim.g.mkdp_combine_preview = 1 -- reuse one browser tab across buffers
      vim.g.mkdp_refresh_slow = 0 -- live update as you type
      vim.g.mkdp_page_title = '${name}'
    end,
  },
}
