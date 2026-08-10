return {
  'pwntester/octo.nvim',
  cmd = 'Octo',
  opts = {
    -- or "fzf-lua" or "snacks" or "default"
    picker = 'telescope',
    -- bare Octo command opens picker of commands
    enable_builtin = true,
    -- use local files on the right side of reviews
    use_local_fs = true,
  },
  -- ponytail: upstream notify.lua passes non-string msgs (nil from commands.lua
  -- line 1258 when a group is called with no action) to vim.notify, which makes
  -- nvim_echo throw "Invalid chunk: expected Array with 1 or 2 Strings" and
  -- clobbers the real error. Coerce once at the boundary; survives plugin updates.
  config = function(_, opts)
    require('octo').setup(opts)
    local notify = require('octo.notify')
    local raw = notify.notify
    notify.notify = function(msg, level)
      return raw(msg == nil and '' or tostring(msg), level)
    end
  end,
  keys = {
    {
      '<leader>oi',
      '<CMD>Octo issue list<CR>',
      desc = 'List GitHub Issues',
    },
    {
      '<leader>op',
      '<CMD>Octo pr list<CR>',
      desc = 'List GitHub PullRequests',
    },
    {
      '<leader>od',
      '<CMD>Octo discussion list<CR>',
      desc = 'List GitHub Discussions',
    },
    {
      '<leader>on',
      '<CMD>Octo notification list<CR>',
      desc = 'List GitHub Notifications',
    },
    {
      '<leader>os',
      function()
        require('octo.utils').create_base_search_command { include_current_repo = true }
      end,
      desc = 'Search GitHub',
    },

    -- review (<leader>or…)
    { '<leader>ors', '<CMD>Octo review start<CR>', desc = 'Review: start' },
    { '<leader>orr', '<CMD>Octo review resume<CR>', desc = 'Review: resume' },
    { '<leader>ord', '<CMD>Octo review discard<CR>', desc = 'Review: discard' },
    { '<leader>orS', '<CMD>Octo review submit<CR>', desc = 'Review: submit' },
    { '<leader>orb', '<CMD>Octo review browse<CR>', desc = 'Review: browse' },
    { '<leader>orc', '<CMD>Octo review comments<CR>', desc = 'Review: pending comments' },
    { '<leader>ort', '<CMD>Octo review thread<CR>', desc = 'Review: threads' },
    { '<leader>orC', '<CMD>Octo review commit<CR>', desc = 'Review: pick commit' },
    { '<leader>orx', '<CMD>Octo review close<CR>', desc = 'Review: close layout' },

    -- comments (<leader>oc…)
    { '<leader>oca', '<CMD>Octo comment add<CR>', desc = 'Comment: add' },
    { '<leader>ocs', '<CMD>Octo comment suggest<CR>', desc = 'Comment: suggestion' },
    { '<leader>ocr', '<CMD>Octo comment reply<CR>', desc = 'Comment: reply' },
    { '<leader>oce', '<CMD>Octo comment edits<CR>', desc = 'Comment: edit' },
    { '<leader>ocd', '<CMD>Octo comment delete<CR>', desc = 'Comment: delete' },
    { '<leader>ocu', '<CMD>Octo comment url<CR>', desc = 'Comment: copy URL' },
    { '<leader>oco', '<CMD>Octo comment reference<CR>', desc = 'Comment: ref in new issue' },

    -- threads (<leader>ot…)
    { '<leader>otR', '<CMD>Octo thread resolve<CR>', desc = 'Thread: resolve' },
    { '<leader>otu', '<CMD>Octo thread unresolve<CR>', desc = 'Thread: unresolve' },

    -- labels (<leader>ol…)
    { '<leader>ola', '<CMD>Octo label add<CR>', desc = 'Label: add' },
    { '<leader>olr', '<CMD>Octo label remove<CR>', desc = 'Label: remove' },
    { '<leader>olc', '<CMD>Octo label create<CR>', desc = 'Label: create' },

    -- reactions (<leader>re…)
    { '<leader>re+', '<CMD>Octo reaction thumbs_up<CR>', desc = 'React 👍' },
    { '<leader>re-', '<CMD>Octo reaction thumbs_down<CR>', desc = 'React 👎' },
    { '<leader>reh', '<CMD>Octo reaction heart<CR>', desc = 'React ❤️' },
    { '<leader>rer', '<CMD>Octo reaction rocket<CR>', desc = 'React 🚀' },

    -- misc
    { '<leader>oR', '<CMD>Octo repo browser<CR>', desc = 'Open repo in browser' },
    { '<leader>ou', '<CMD>Octo repo url<CR>', desc = 'Copy repo URL' },
  },
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    -- OR "ibhagwan/fzf-lua",
    -- OR "folke/snacks.nvim",
    'nvim-tree/nvim-web-devicons',
  },
}
