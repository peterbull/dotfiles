---@class runme.Session
---@field proc vim.SystemObj
---@field id string
---@field alive boolean
---@field private buffer string
---@field private stderr string[]
local Session = {}
Session.__index = Session

local M = {}

---@param s string
---@return string
local function strip_cr(s)
  return (s:gsub('\r$', ''))
end

---@param opts { cmd: string[], cwd: string, env?: table<string,string>, id: string, on_message: fun(msg: table), on_exit: fun(code: integer, stderr: string) }
---@return runme.Session
function M.start(opts)
  local self = setmetatable({ id = opts.id, alive = true, buffer = '', stderr = {} }, Session)

  local function on_stdout(err, chunk)
    if err then
      vim.schedule(function()
        opts.on_message { type = 'runme_stream_error', error = err }
      end)
      return
    end
    if not chunk then
      return
    end
    self.buffer = self.buffer .. chunk
    -- RPC framing is LF-only; JSON strings may legally contain U+2028/2029.
    while true do
      local nl = self.buffer:find('\n', 1, true)
      if not nl then
        break
      end
      local line = strip_cr(self.buffer:sub(1, nl - 1))
      self.buffer = self.buffer:sub(nl + 1)
      if line ~= '' then
        local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
        vim.schedule(function()
          if ok and type(msg) == 'table' then
            opts.on_message(msg)
          else
            opts.on_message { type = 'runme_stream_error', error = 'unparsable line: ' .. line:sub(1, 200) }
          end
        end)
      end
    end
  end

  local function on_stderr(_, chunk)
    if chunk then
      table.insert(self.stderr, chunk)
      if #self.stderr > 200 then
        table.remove(self.stderr, 1)
      end
    end
  end

  self.proc = vim.system(opts.cmd, {
    cwd = opts.cwd,
    env = opts.env,
    stdin = true,
    stdout = on_stdout,
    stderr = on_stderr,
    text = true,
  }, function(obj)
    self.alive = false
    vim.schedule(function()
      opts.on_exit(obj.code, table.concat(self.stderr))
    end)
  end)
  return self
end

---@param msg table
---@return boolean sent
function Session:send(msg)
  if not self.alive then
    return false
  end
  self.proc:write(vim.json.encode(msg) .. '\n')
  return true
end

---@param message string
---@param streaming boolean
function Session:prompt(message, streaming)
  self:send { type = 'prompt', message = message, streamingBehavior = streaming and 'followUp' or nil }
end

function Session:abort()
  self:send { type = 'abort' }
end

function Session:stop()
  if self.alive then
    self.proc:kill 'sigterm'
  end
end

return M
