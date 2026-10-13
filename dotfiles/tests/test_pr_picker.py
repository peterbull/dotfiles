"""PR picker contracts: python3 -B -m unittest discover -s dotfiles/tests -p test_pr_picker.py -v."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

CONFIG = Path(__file__).resolve().parents[2] / '.config/nvim'


def find_nvim():
    explicit = os.environ.get('DOTFILES_TEST_NVIM')
    if explicit:
        binary = Path(explicit).expanduser().resolve()
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise ValueError('DOTFILES_TEST_NVIM must name an existing executable')
        return binary
    bob = Path.home() / '.local/share/bob'
    try:
        selected = (bob / 'used').read_text().strip()
    except OSError:
        return None
    if not selected or Path(selected).name != selected or selected in ('.', '..'):
        return None
    binary = bob / selected / 'bin/nvim'
    return binary if binary.is_file() and os.access(binary, os.X_OK) else None


NVIM = find_nvim()
HARNESS = r'''
local actual_system = vim.system
local notices, calls, pending = {}, {}, {}
vim.notify = function(message) notices[#notices + 1] = message end
vim.system = function(argv, opts, callback)
  calls[#calls + 1] = {argv = argv, cwd = opts.cwd}
  pending[#pending + 1] = callback
end
local function reply(value, code)
  local cb = table.remove(pending, 1)
  assert(cb, 'no pending command')
  cb({code = code or 0, stdout = type(value) == 'string' and value or vim.json.encode(value), stderr = code and 'command failed' or ''})
  vim.wait(100, function() return false end, 10)
end
local picker, mappings, selected, command
package.preload['telescope.pickers'] = function() return {new = function(_, opts)
  picker = opts
  return {find = function() opts.attach_mappings(1, function(mode, key, fn) mappings = mappings or {}; mappings[key] = fn end) end}
end} end
package.preload['telescope.finders'] = function() return {new_table = function(opts) return opts end} end
package.preload['telescope.previewers'] = function() return {new_buffer_previewer = function(opts) return opts end} end
package.preload['telescope.actions'] = function() return {close = function() end, select_default = {replace = function(_, fn) selected = fn end}} end
package.preload['telescope.actions.state'] = function() return {get_selected_entry = function() return picker.finder.entry_maker(picker.finder.results[1]) end} end
package.preload['telescope.config'] = function() return {values = {generic_sorter = function() return {scoring_function = function() return 1 end} end}} end
package.preload['diffview'] = function() return {open = function(value) command = value end} end
local module = require('config.pr_picker')
module.open()
reply('/tmp/repo with spaces\n')
reply({nameWithOwner = 'upstream/repo', url = 'https://github.com/upstream/repo'})
'''


@unittest.skipUnless(NVIM, 'Provision Bob Neovim or set DOTFILES_TEST_NVIM')
class PrPickerTests(unittest.TestCase):
    def lua(self, body):
        with tempfile.TemporaryDirectory() as temp:
            script = Path(temp) / 'test.lua'
            script.write_text('package.path = ' + repr(str(CONFIG / 'lua/?.lua') + ';') + ' .. package.path\n' + HARNESS + body)
            result = subprocess.run([str(NVIM), '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)], text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_group_priority_dedup_and_captured_repository(self):
        self.lua(r'''
reply({{number=2,title='mine',author={login='me'},url='u2'}})
reply({{number=2,title='duplicate',url='u2'},{number=3,title='review',author={login='other'},url='u3'}})
reply({{number=3,title='duplicate',url='u3'},{number=4,title='repo',author={login='other'},url='u4'}})
assert(#picker.finder.results == 3)
assert(picker.finder.results[1].number == 2 and picker.finder.results[2].number == 3 and picker.finder.results[3].number == 4)
assert(picker.finder.results[1].group == 'Mine' and picker.finder.results[2].group == 'Review requested')
for i=2,#calls do assert(calls[i].cwd == '/tmp/repo with spaces') end
assert(vim.tbl_contains(calls[3].argv, '@me'))
assert(vim.tbl_contains(calls[4].argv, 'review-requested:@me'))
assert(mappings['<M-b>'] and mappings['<C-y>'])
assert(picker.sorter:scoring_function('x','x',{value={rank=1}}) < picker.sorter:scoring_function('x','x',{value={rank=2}}))
''')

    def test_pushed_pr_refs_and_immutable_diff(self):
        self.lua(r'''
reply({{number=7,title='fork',author={login='me'},url='url'}})
reply({})
reply({})
vim.fn.getcwd = function() return '/unrelated/new/cwd' end
selected()
reply({baseRefName='stack/base',number=7})
local fetch = calls[#calls].argv
assert(vim.tbl_contains(fetch, 'https://github.com/upstream/repo'))
assert(vim.tbl_contains(fetch, '+refs/heads/stack/base:refs/pr-picker/7/base'))
assert(vim.tbl_contains(fetch, '+refs/pull/7/head:refs/pr-picker/7/head'))
reply('')
reply(string.rep('a',40)..'\n')
reply(string.rep('b',40)..'\n')
assert(command[1] == '-C=/tmp/repo with spaces')
assert(command[2] == string.rep('a',40)..'...'..string.rep('b',40))
''')

    def test_failures_stop_work_without_opening_diff(self):
        self.lua(r'''
reply({{number=7,title='fork',author={login='me'},url='url'}})
reply({})
reply({})
selected()
reply('', 1)
assert(#pending == 0 and command == nil)
assert(#notices > 0 and notices[#notices]:find('command failed',1,true))
''')

    def test_invalid_json_reports_error(self):
        self.lua(r'''
reply('invalid json')
assert(#pending == 0 and picker == nil)
assert(#notices > 0)
''')

    def test_real_git_fetch_fork_and_stacked_base_without_checkout_changes(self):
        with tempfile.TemporaryDirectory(prefix='pr picker ') as temp:
            root = Path(temp)
            upstream, fork, checkout = root / 'upstream.git', root / 'fork', root / 'checkout'
            def git(*args, cwd=None):
                return subprocess.check_output(['git', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', *args], cwd=cwd, text=True, stderr=subprocess.DEVNULL).strip()
            git('init', '--bare', str(upstream))
            git('clone', str(upstream), str(fork))
            git('config', 'user.name', 'fixture', cwd=fork)
            git('config', 'user.email', 'fixture@example.com', cwd=fork)
            (fork / 'file').write_text('base\n')
            git('add', 'file', cwd=fork)
            git('commit', '-m', 'base', cwd=fork)
            git('branch', '-M', 'main', cwd=fork)
            git('push', 'origin', 'main', cwd=fork)
            git('checkout', '-b', 'stack/base', cwd=fork)
            (fork / 'stack').write_text('stacked base\n')
            git('add', 'stack', cwd=fork)
            git('commit', '-m', 'stack', cwd=fork)
            base = git('rev-parse', 'HEAD', cwd=fork)
            git('push', 'origin', 'stack/base', cwd=fork)
            git('checkout', '-b', 'fork-feature', cwd=fork)
            (fork / 'feature').write_text('fork change\n')
            git('add', 'feature', cwd=fork)
            git('commit', '-m', 'feature', cwd=fork)
            head = git('rev-parse', 'HEAD', cwd=fork)
            git('push', 'origin', 'HEAD:refs/pull/7/head', cwd=fork)
            git('clone', '-b', 'main', str(upstream), str(checkout))
            (checkout / 'file').write_text('dirty checkout\n')
            before = git('status', '--porcelain', cwd=checkout)
            def fixture_lua(body):
                fixture = HARNESS.replace("reply('/tmp/repo with spaces\\n')", 'reply(' + repr(str(checkout)) + ')').replace("https://github.com/upstream/repo", str(upstream))
                with tempfile.TemporaryDirectory() as directory:
                    script = Path(directory) / 'test.lua'
                    script.write_text('package.path = ' + repr(str(CONFIG / 'lua/?.lua') + ';') + ' .. package.path\n' + fixture + body)
                    result = subprocess.run([str(NVIM), '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)], text=True, capture_output=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            fixture_lua(r''' 
reply({{number=7,title='fork',author={login='me'},url='url'}})
reply({})
reply({})
vim.system = function(argv, opts, cb)
  if argv[1] == 'gh' then
    cb({code=0,stdout=vim.json.encode({baseRefName='stack/base'}),stderr=''})
  else
    return actual_system(argv, opts, cb)
  end
end
selected()
assert(vim.wait(5000, function() return command ~= nil or #notices > 0 end, 10))
assert(command, vim.inspect(notices))
''')
            self.assertEqual(git('status', '--porcelain', cwd=checkout), before)
            self.assertEqual(git('rev-parse', 'refs/pr-picker/7/base', cwd=checkout), base)
            self.assertEqual(git('rev-parse', 'refs/pr-picker/7/head', cwd=checkout), head)
            self.assertEqual(git('diff', '--name-only', base + '...' + head, cwd=checkout), 'feature')
