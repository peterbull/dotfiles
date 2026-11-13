local directory = vim.fn.expand '~/peter-projects/runme'

return {
  {
    dir = directory,
    enabled = vim.fn.filereadable(directory .. '/lua/runme/init.lua') == 1,
    name = 'runme',
    main = 'runme',
    cmd = { 'RunMe', 'RunMeHistory', 'RunMeResume', 'RunMeCancel', 'RunMeClear', 'RunMeScratch', 'RunMeEval' },
    opts = {
      keymap = false,
      resume_keymap = false,
      resume_hint = '<leader>hR',
      pi = {
        executable = vim.fn.stdpath 'config' .. '/bin/pi-mise',
        model = 'openai-codex/gpt-6.1-sol',
        thinking = 'medium',
      },
      pi_config_dir = '~/peter-projects/pi-config',
      ruby = { cmd = { 'mise', 'exec', '--', 'bundle', 'exec', 'rails', 'runner' } },
    },
    keys = {
      {
        '<leader>hr',
        function()
          require('runme').show()
        end,
        mode = 'n',
        desc = 'RunMe: run / query / break here',
      },
      {
        '<leader>hr',
        function()
          require('runme').visual()
        end,
        mode = 'x',
        desc = 'RunMe: run / query the selection',
      },
      {
        '<leader>hR',
        function()
          require('runme').resume()
        end,
        mode = 'n',
        desc = 'RunMe: reopen panel',
      },
      {
        '<leader>he',
        '<cmd>RunMeScratch<cr>',
        mode = 'n',
        desc = 'RunMe: Ruby scratch (warm Rails)',
      },
      {
        '<leader>he',
        ':RunMeEval<cr>',
        mode = 'x',
        desc = 'RunMe: evaluate selection (warm Rails)',
      },
    },
  },
}
