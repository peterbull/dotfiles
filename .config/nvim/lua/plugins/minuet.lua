return {
  'milanglacier/minuet-ai.nvim',
  event = 'InsertEnter',
  config = function()
    -- Load API keys from ~/.env
    local env_file = vim.fn.expand '~/.env'
    if vim.fn.filereadable(env_file) == 1 then
      for line in io.lines(env_file) do
        local key, value = line:match '^%s*([%w_]+)%s*=%s*(.+)$'
        if key and value and vim.env[key] == nil then
          -- Strip surrounding quotes if present
          value = value:gsub('^["\']', ''):gsub('["\']$', '')
          vim.env[key] = value
        end
      end
    end

    require('minuet').setup {
      provider = 'openai_fim_compatible',
      request_timeout = 3,
      throttle = 1000,
      debounce = 400,
      n_completions = 3,
      context_window = 16000,
      context_ratio = 0.75,
      notify = 'warn',
      virtualtext = {
        auto_trigger_ft = { '*' },
        keymap = {
          accept = '<C-y>',
          next = '<A-]>',
          prev = '<A-[>',
          dismiss = '<A-e>',
        },
      },
      provider_options = {
        openai_fim_compatible = {
          api_key = 'DEEPSEEK_API_KEY',
          name = 'deepseek',
          model = 'deepseek-v4-flash',
          optional = {
            max_tokens = 256,
            top_p = 0.9,
          },
        },
      },
    }
  end,
}
