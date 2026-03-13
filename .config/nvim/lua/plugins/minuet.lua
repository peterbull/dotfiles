return {
  'milanglacier/minuet-ai.nvim',
  enabled = false,
  dependencies = { 'nvim-lua/plenary.nvim' },
  event = 'InsertEnter',
  opts = {
    provider = 'openai_fim_compatible',
    n_completions = 1,
    context_window = 4096,
    request_timeout = 10,
    throttle = 1500,
    debounce = 500,
    notify = 'warn',
    provider_options = {
      openai_fim_compatible = {
        api_key = 'TERM',
        name = 'Ollama',
        end_point = 'http://localhost:11434/v1/completions',
        model = 'qwen2.5-coder:7b',
        optional = {
          max_tokens = 256,
          top_p = 0.9,
        },
      },
    },
    virtualtext = {
      auto_trigger_ft = { '*' },
      keymap = {
        accept = '<A-a>',
        accept_line = '<A-l>',
        next = '<A-]>',
        prev = '<A-[>',
        dismiss = '<A-e>',
      },
    },
  },
}
