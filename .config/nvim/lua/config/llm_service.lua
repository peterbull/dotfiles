local M = {}

---@class LlmServiceConfig
---@field base_url string  Base URL for the chat completions API (e.g. "https://api.deepseek.com/v1")
---@field api_key  string  API key for Bearer auth
---@field model    string  Model name to use
---@field timeout  number  Request timeout in milliseconds (default 20000)

---@type LlmServiceConfig
M.config = {
  -- base_url = "https://rig.ctmdev.us/v1",
  base_url = 'https://rig.ctmdev.us/v1',
  api_key = nil,
  -- model = 'GLM-5.2',
  model = 'deepseek-v4-flash',
  timeout = 20000,
}

---Merge user options into the default config.
---@param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

---Send a chat completion request asynchronously.
---@param messages  table[]  Array of { role: string, content: string }
---@param opts?     table    Optional overrides: model, max_tokens, temperature, timeout
---@param callback  fun(answer: string|nil, err: string|nil)
function M.chat(messages, opts, callback)
  if type(opts) == 'function' then
    callback = opts
    opts = {}
  end
  opts = opts or {}

  local body = vim.json.encode {
    model = opts.model or M.config.model,
    messages = messages,
    max_tokens = opts.max_tokens or 256,
    temperature = opts.temperature or 0,
    stream = false,
  }

  local timeout_secs = math.floor((opts.timeout or M.config.timeout) / 1000)
  local args = {
    'curl',
    '-s',
    '--max-time',
    tostring(timeout_secs),
    '-X',
    'POST',
    M.config.base_url .. '/chat/completions',
    '-H',
    'Content-Type: application/json',
    '-H',
    'Authorization: Bearer ' .. M.config.api_key,
    '-d',
    body,
  }

  vim.system(args, { text = true }, function(obj)
    if obj.code ~= 0 then
      local detail = obj.stderr or 'curl exited ' .. tostring(obj.code)
      callback(nil, detail)
      return
    end

    local ok, data = pcall(vim.json.decode, obj.stdout)
    if not ok then
      callback(nil, 'Failed to parse API response')
      return
    end

    if data.error then
      callback(nil, data.error.message or 'API error')
      return
    end

    local content = data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content

    if content then
      callback(vim.trim(content))
    else
      callback(nil, 'Unexpected response format')
    end
  end)
end

return M
