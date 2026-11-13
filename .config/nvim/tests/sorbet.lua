local config_root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(config_root)
local sorbet = require 'config.sorbet'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/sorbet', 'p')
root = assert(vim.uv.fs_realpath(root))

local function file(path)
  vim.fn.mkdir(vim.fs.dirname(root .. '/' .. path), 'p')
  vim.fn.writefile({}, root .. '/' .. path)
  return vim.fn.bufadd(root .. '/' .. path)
end

local capture = file 'app/classes/live_conversation_capture/state.rb'
local coordinator = file 'app/classes/live_conversation_capture.rb'
local mutation = file 'app/graphql/mutations/live_conversations/capture_mutation.rb'
local unrelated = file 'app/services/live_conversations/activity_scope.rb'
local similar = file 'app/classes/live_conversation_capture_extra/state.rb'
local dependency = file 'sorbet/rbi/dependency.rbi'
file 'Gemfile'
vim.fn.writefile({
  '# Capture scope',
  '--parser=prism',
  '--enable-experimental-rbs-comments',
  'app/classes/live_conversation_capture',
  '--file=app/classes/live_conversation_capture.rb',
  '--file=app/graphql/mutations/live_conversations/capture_mutation.rb',
  '--file=sorbet/rbi/dependency.rbi',
}, root .. '/sorbet/config')

local function expect_root(buf, expected)
  local actual
  sorbet.root_dir(buf, function(value)
    actual = value
  end)
  assert(actual == expected, vim.inspect { buffer = vim.api.nvim_buf_get_name(buf), expected = expected, actual = actual })
end

for _, buf in ipairs { capture, coordinator, mutation, dependency } do
  expect_root(buf, root)
end
expect_root(unrelated, nil)
expect_root(similar, nil)

local revision = vim.fn.bufadd('fugitive://' .. root .. '/.git//HEAD/app/classes/live_conversation_capture.rb')
expect_root(revision, nil)
expect_root(vim.fn.bufadd(root .. '/app/classes/live_conversation_capture/missing.rb'), nil)

vim.fn.writefile({ '--parser=prism' }, root .. '/sorbet/config')
expect_root(unrelated, root)

vim.fn.writefile({ '--dir=.' }, root .. '/sorbet/config')
expect_root(unrelated, root)

vim.fn.writefile({ '--dir=app/classes/live_conversation_capture' }, root .. '/sorbet/config')
expect_root(capture, root)
expect_root(unrelated, nil)

vim.fn.writefile({ '--file=' .. root .. '/app/classes/live_conversation_capture.rb' }, root .. '/sorbet/config')
expect_root(coordinator, root)
expect_root(capture, nil)
print 'PASS Sorbet attachment follows configured inputs and excludes revision buffers'
