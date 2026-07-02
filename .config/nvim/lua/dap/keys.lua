local M = {}
M.keys = {
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
    '<leader>dB',
    function()
      require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
    end,
    desc = 'Breakpoint Condition',
  },
  {
    '<leader>dh',
    function()
      require('dap').set_breakpoint(nil, vim.fn.input 'Breakpoint hit number: ')
    end,
    desc = 'Breakpoint Hit Condition',
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
    '<leader>dk',
    function()
      require('dap').down()
    end,
    desc = 'Down',
  },
  {
    '<leader>dj',
    function()
      require('dap').up()
    end,
    desc = 'Up',
  },
  {
    '<F4>',
    function()
      require('dap').down()
    end,
    desc = 'Down',
  },
  {
    '<F3>',
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
      require('dap').repl.toggle({}, 'botright vsplit')
    end,
    desc = 'Toggle REPL (right vertical split)',
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
    '<leader>dsi',
    function()
      require('dap').up()
    end,
    desc = 'Debug: DAP Stack UP',
  },
  {
    '<leader>dso',
    function()
      require('dap').down()
    end,
    desc = 'Debug: DAP Stack DOWN',
  },
  {
    '<leader>dN',
    function()
      require('osv').launch { port = 8086 }
    end,
    desc = 'Launch [N]vim Debug Server',
  },
  {
    '<leader>dE',
    function()
      vim.cmd 'DapEval'
    end,
    desc = 'Launch [E]val Session',
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
  {
    '<leader>dv',
    function()
      require('nvim-dap-virtual-text').toggle()
    end,
    desc = 'Toggle DAP Virtual Text',
  },
}

return M
