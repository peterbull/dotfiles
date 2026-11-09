local directory = vim.fn.expand '~/peter-projects/nudge.nvim'

local actions = {
  { '<leader>ng', 'goal', 'set the goal and plan' },
  { '<leader>nn', 'next', 'what next?' },
  { '<leader>nh', 'hint', 'more hint' },
  { '<leader>na', 'ask', 'ask about this step' },
  { '<leader>nr', 'review', 'review my code' },
  { '<leader>nd', 'done', 'step done' },
  { '<leader>nR', 'reveal', 'reveal (typed toll)' },
  { '<leader>nc', 'card', 'show the step card' },
  { '<leader>np', 'plan', 'edit the plan' },
}

local keys = {}
for _, action in ipairs(actions) do
  keys[#keys + 1] = { action[1], '<cmd>Nudge ' .. action[2] .. '<cr>', desc = 'Nudge: ' .. action[3] }
end

return {
  {
    dir = directory,
    enabled = vim.fn.filereadable(directory .. '/lua/nudge/init.lua') == 1,
    name = 'nudge.nvim',
    main = 'nudge',
    cmd = 'Nudge',
    keys = keys,
    opts = {
      keys = false,
      step = { min_lines = 1, max_lines = 10 },
    },
  },
}
