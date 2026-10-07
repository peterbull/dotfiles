"""Isolated config contracts: python3 -B -m unittest discover -s dotfiles/tests -p test_nvim_portability.py -v."""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / ".config/nvim"
def find_test_nvim():
    explicit = os.environ.get("DOTFILES_TEST_NVIM")
    if explicit:
        binary = Path(explicit).expanduser().resolve()
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise ValueError("DOTFILES_TEST_NVIM must name an existing executable")
        return binary
    bob = Path.home() / ".local/share/bob"
    try:
        selected = (bob / "used").read_text().strip()
    except OSError:
        return None
    if not selected or Path(selected).name != selected or selected in (".", ".."):
        return None
    binary = bob / selected / "bin/nvim"
    return binary if binary.is_file() and os.access(binary, os.X_OK) else None


NVIM = find_test_nvim()
QUERY_HASHES = {
    "locals.scm": "3fa3d3719f902cbb787f1d72a6cde64b339628467dc0f21d263d963340780bf8",
    "highlights.scm": "74b7e3fb0e7fbb24c8842d5f10c487757c47e3b122bbd3d2800c6b6b89847d99",
    "folds.scm": "a74c37acf47515e1ff243db94fe5adfe6e3fdd8a16c528abe28a26411128ee33",
    "injections.scm": "1f62ce8a9a263e42b85d82ce5515c30b47ce199c8a71597255e83a1439a11c7c",
}


@unittest.skipUnless(NVIM is not None, "Provision Bob Neovim or set DOTFILES_TEST_NVIM; editor checks not run")
class NvimPortabilityTests(unittest.TestCase):
    def setUp(self):
        assert NVIM is not None
        self.assertTrue(NVIM.is_file(), "Installed Bob Neovim is required")
        temp = tempfile.TemporaryDirectory(prefix="nvim portability ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.config = self.home / ".config/nvim"
        shutil.copytree(CONFIG / "lua", self.config / "lua")
        self.bin = self.root / "empty bin"
        self.bin.mkdir()
        self.env = {"HOME": str(self.home), "PATH": str(self.bin), "LC_ALL": "C",
                    "XDG_CONFIG_HOME": str(self.home / ".config"),
                    "XDG_DATA_HOME": str(self.home / ".local/share"),
                    "XDG_STATE_HOME": str(self.home / ".local/state"),
                    "XDG_CACHE_HOME": str(self.home / ".cache"),
                    "XDG_RUNTIME_DIR": str(self.root / "runtime"),
                    "TMPDIR": str(self.root / "tmp")}
        for key in ("XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "TMPDIR"):
            Path(self.env[key]).mkdir(parents=True)
        Path(self.env["XDG_RUNTIME_DIR"]).chmod(0o700)

    def file(self, relative, executable=False):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("fixture only\n")
        if executable:
            path.chmod(0o755)
        return path

    def lua(self, body):
        script = self.root / "test.lua"
        script.write_text('''
vim.opt.runtimepath = vim.env.XDG_CONFIG_HOME .. '/nvim,' .. vim.env.VIMRUNTIME
package.path = vim.env.XDG_CONFIG_HOME .. '/nvim/lua/?.lua;' .. vim.env.XDG_CONFIG_HOME .. '/nvim/lua/?/init.lua;' .. package.path
local function forbidden() error('Unexpected process spawn') end
vim.fn.system = forbidden
vim.fn.systemlist = forbidden
vim.fn.jobstart = forbidden
vim.system = forbidden
vim.uv.spawn = forbidden
package.preload['dap'] = function() return { ABORT = {}, configurations = {}, adapters = {} } end
package.preload['dap.utils'] = function() return { pick_process = function() end } end
local messages = {}
vim.notify = function(msg) messages[#messages + 1] = msg end
local ok, err = xpcall(function()
''' + body + '''
end, debug.traceback)
if not ok then io.stderr:write(err .. '\\n'); vim.cmd('cquit 1') else vim.cmd('qa!') end
''')
        command = ["/usr/bin/env", "-i"] + [f"{k}={v}" for k, v in self.env.items()]
        result = subprocess.run(command + [str(NVIM), "--headless", "-u", "NONE", "-i", "NONE",
                                           "--noplugin", "-l", str(script)],
                                cwd=self.home, env={}, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_provider_absent_disables_discovery(self):
        self.lua("require('config.options'); assert(vim.g.loaded_python3_provider == 0); assert(vim.g.python3_host_prog == nil)")

    def test_provider_present_uses_expanded_executable(self):
        self.file(".virtualenvs/nvim/bin/python3", executable=True)
        self.lua("require('config.options'); assert(vim.g.loaded_python3_provider ~= 0); assert(vim.g.python3_host_prog == vim.env.HOME .. '/.virtualenvs/nvim/bin/python3')")

    def test_provider_non_executable_disables_discovery(self):
        self.file(".virtualenvs/nvim/bin/python3")
        self.lua("require('config.options'); assert(vim.g.loaded_python3_provider == 0)")

    def test_jupyter_absent_is_disabled_and_lazy_require(self):
        self.lua("""
package.preload['jupyter'] = function() error('Must not eagerly require') end
local spec = require('plugins.jupyter')[1]
assert(spec.enabled == false)
assert(spec.dir == vim.env.HOME .. '/peter-projects/nvim-jupyter')
""")

    def test_jupyter_present_preserves_images(self):
        self.file("peter-projects/nvim-jupyter/lua/jupyter/init.lua")
        self.lua("""
local loads, options = 0, nil
package.preload['jupyter'] = function() loads = loads + 1; return { setup = function(o) options = o end } end
local spec = require('plugins.jupyter')[1]
assert(spec.enabled == true and loads == 0)
spec.config()
assert(loads == 1 and options.images == true)
""")

    def treesitter(self, expected):
        self.lua("""
local parsers, autocmd = {}, nil
package.preload['nvim-treesitter.parsers'] = function() return { get_parser_configs = function() return parsers end } end
package.preload['nvim-treesitter.configs'] = function() return { setup = function() end } end
vim.api.nvim_create_autocmd = function(_, o) autocmd = o end
local spec = require('plugins.treesitter')
spec.config(nil, spec.opts)
""" + expected)

    def test_parsers_absent_no_registration_or_autocmd(self):
        self.treesitter("assert(parsers.reef == nil and parsers.mustache == nil and autocmd == nil)")

    def test_parser_partial_source_no_registration(self):
        self.file("peter-projects/tree-sitter-mustache/src/parser.c")
        self.treesitter("assert(parsers.mustache == nil and autocmd == nil)")

    def test_available_parser_missing_compiled_parser_is_safe(self):
        for name in ("parser.c", "scanner.c"):
            self.file("peter-projects/tree-sitter-mustache/src/" + name)
        self.treesitter("""
assert(parsers.reef == nil and parsers.mustache ~= nil)
assert(vim.deep_equal(autocmd.pattern, { 'mustache' }))
local custom_autocmd = autocmd
vim.treesitter.start = function() error('Parser not compiled') end
assert(pcall(custom_autocmd.callback, { buf = 1 }))
local started = false
vim.treesitter.start = function(buf) started = buf == 1 end
custom_autocmd.callback({ buf = 1 }); assert(started)
""")

    def test_reef_available_registers_only_reef(self):
        self.file("peter-projects/tree-sitter-reef/src/parser.c")
        self.treesitter("assert(parsers.reef ~= nil and parsers.mustache == nil); assert(vim.deep_equal(autocmd.pattern, {'reef'}))")

    def test_modern_lsp_configuration_precedes_allowlisted_enable(self):
        self.lua("""
local tool_opts, mason_opts, enabled = nil, nil, {}
local capabilities = { textDocument = { completion = { completionItem = { snippetSupport = true } } } }
package.preload['blink.cmp'] = function() return { get_lsp_capabilities = function() return capabilities end } end
package.preload['mason-tool-installer'] = function() return { setup = function(o) tool_opts = o end } end
vim.lsp.enable = function(name) enabled[name] = true end
package.preload['mason-lspconfig'] = function() return { setup = function(o)
  mason_opts = o
  assert(o.handlers == nil and o.automatic_enable.exclude == nil)
  for _, name in ipairs(o.automatic_enable) do
    assert(vim.lsp.config[name].capabilities.textDocument.completion.completionItem.snippetSupport, name)
    assert(name ~= 'vtsls' and name ~= 'ruby_lsp' and name ~= 'sorbet' and name ~= 'ts_ls')
  end
end } end
require('plugins.lsp').config()
assert(tool_opts and mason_opts)
for _, name in ipairs({'clangd','ty','html','helm_ls','emmet_language_server','graphql','lua_ls','zls','terraformls','gopls'}) do
  assert(vim.tbl_contains(mason_opts.automatic_enable, name), name)
  assert(vim.tbl_contains(tool_opts.ensure_installed, name), name)
end
assert(not vim.tbl_contains(tool_opts.ensure_installed, 'vtsls'))
assert(not vim.tbl_contains(tool_opts.ensure_installed, 'ruby_lsp'))
for _, name in ipairs({'stylua','prettier','black','isort','shfmt'}) do assert(vim.tbl_contains(tool_opts.ensure_installed, name), name) end
assert(vim.deep_equal(vim.lsp.config.zls.cmd, {'zls'}))
assert(vim.lsp.config.lua_ls.settings.Lua.diagnostics.globals[1] == 'vim')
assert(vim.lsp.config.html.filetypes[1] == 'html')
assert(vim.lsp.config.gopls.settings.gopls.semanticTokens == true)
assert(vim.lsp.config.ruby_lsp.cmd[1] == 'mise' and enabled.ruby_lsp and enabled.sorbet)
assert(vim.lsp.config.sorbet.capabilities.textDocument.completion.completionItem.snippetSupport)
local function initialize_ty()
  local cfg = vim.deepcopy(vim.lsp.config.ty)
  local sent_settings
  cfg.name = 'ty-fixture'
  cfg.cmd = function() return {
    request = function(method, _, cb)
      assert(method == 'initialize'); cb(nil, { capabilities = {} }); return true, 1
    end,
    notify = function(method, params)
      if method == 'workspace/didChangeConfiguration' then sent_settings = params.settings end
      return true
    end,
    is_closing = function() return false end,
    terminate = function() end,
  } end
  local client = require('vim.lsp.client').create(cfg)
  client:initialize()
  return client, sent_settings
end
local absent = initialize_ty(); assert(absent.settings.python == nil)
package.preload['venv-selector'] = function() return { venv = function() return '/project venv' end } end
local present, sent = initialize_ty()
assert(present.settings.python.pythonPath == '/project venv/bin/python')
assert(sent.python.pythonPath == '/project venv/bin/python')
""")

    def test_adapter_packages_have_one_owner_and_optional_switch(self):
        self.lua("""
local tools = require('config.mason-tools')
for _, name in ipairs({'debugpy','bash-debug-adapter','js-debug-adapter','codelldb','delve','cpptools'}) do
  assert(vim.tbl_contains(tools.ensure_installed(), name), name)
end
vim.g.dotfiles_dap_tools = false
for _, name in ipairs({'debugpy','bash-debug-adapter','js-debug-adapter','codelldb','delve','cpptools'}) do
  assert(not vim.tbl_contains(tools.ensure_installed(), name), name)
end
local debug = require('plugins.debug')[1]
for _, dep in ipairs(debug.dependencies) do
  if type(dep) == 'table' then
    assert(dep[1] ~= 'jay-babu/mason-nvim-dap.nvim')
    assert(dep[1] ~= 'mason-org/mason.nvim')
  end
end
""")

    def test_python_adapter_missing_and_mason_owned_present(self):
        self.lua("""
local adapter = require('dap.python').adapters.python
local called = false
adapter(function() called = true end, { request = 'launch' })
assert(not called and messages[#messages]:find('debugpy'))
adapter(function(a) called = a.type == 'server' and a.port == 5679 end, { request = 'attach', connect = {port = 5679} })
assert(called)
""")
        self.file(".local/share/nvim/mason/bin/debugpy-adapter", executable=True)
        self.lua("""
local py = require('dap.python')
py.adapters.python(function(a) assert(a.command == vim.fn.stdpath('data') .. '/mason/bin/debugpy-adapter') end, {request = 'launch'})
local spec = require('plugins.debug')[1]
local setup_path
package.preload['dap-python'] = function() return { setup = function(path) setup_path = path; require('dap').configurations.python = {} end } end
for _, d in ipairs(spec.dependencies) do if type(d) == 'table' and d[1] == 'mfussenegger/nvim-dap-python' then d.config() end end
assert(setup_path == vim.fn.stdpath('data') .. '/mason/bin/debugpy-adapter')
""")

    def test_lldb_and_go_missing_tools_fail_only_at_launch(self):
        self.lua("""
local called = false
require('dap.lldb').adapters.lldb(function() called = true end, {})
assert(not called and messages[#messages]:find('codelldb'))
require('dap.go').adapters.go(function() called = true end, {})
assert(not called and messages[#messages]:find('dlv'))
""")
        self.file(".local/share/nvim/mason/packages/codelldb/extension/adapter/codelldb", executable=True)
        self.file(".local/share/nvim/mason/bin/dlv", executable=True)
        self.lua("""
require('dap.lldb').adapters.lldb(function(a) assert(a.command:find('/mason/', 1, true)) end, {})
require('dap.go').adapters.go(function(a) assert(a.executable.command:find('/mason/', 1, true)) end, {})
""")

    def test_python_project_interpreter_is_independent(self):
        path = self.file(".venv/bin/python", executable=True)
        self.lua("assert(require('dap.python').configurations.python[1].pythonPath() == " + repr(str(path)) + ")")

    def test_sh_missing_adapter_and_script_is_reported_at_launch(self):
        self.lua("""
local a = require('dap.sh').adapters.sh
assert(type(a) == 'function')
local called = false; a(function() called = true end, {})
assert(not called and messages[#messages]:find('bash'))
""")
        self.file(".local/share/nvim/mason/bin/bash-debug-adapter", executable=True)
        for name in ("bash", "cat", "mkfifo", "pkill"):
            (self.bin / name).write_text("fixture only\n")
            (self.bin / name).chmod(0o755)
        self.lua("local called = false; require('dap.sh').adapters.sh(function() called = true end, {}); assert(not called and messages[#messages]:find('bashdb'))")
        self.file(".local/share/nvim/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb")
        self.lua("local called = false; require('dap.sh').adapters.sh(function(a) called = a.type == 'executable' end, {}); assert(called)")

    def test_js_missing_node_or_adapter_script_and_chrome_discovery(self):
        self.lua("""
local ts = require('dap.ts'); assert(type(ts.adapters['pwa-node']) == 'function')
assert(ts.configurations[1].cwd == '${fileDirname}')
local called = false; ts.adapters['pwa-node'](function() called = true end, {})
assert(not called and messages[#messages]:find('node'))
for _, c in ipairs(ts.configurations) do if c.name == 'Launch Chrome (debug profile)' then
  assert(c.runtimeExecutable == nil or type(c.runtimeExecutable) == 'function')
end end
""")
        node = self.bin / "node"
        node.write_text("fixture only\n")
        node.chmod(0o755)
        self.lua("local called = false; require('dap.ts').adapters['pwa-node'](function() called = true end, {}); assert(not called and messages[#messages]:find('dapDebugServer'))")
        self.file(".local/share/nvim/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js")
        self.lua("""
local ts = require('dap.ts'); local cfg = {type = 'node'}
ts.adapters.node(function(a) assert(a.executable.command == 'node') end, cfg)
assert(cfg.type == 'pwa-node')
ts.adapters['pwa-chrome'](function(a) assert(a.executable.args[2] == '${port}') end, {})
""")

    def test_helpers_absent_do_not_add_imports(self):
        self.lua("""
for _, lang in ipairs({'rust', 'zig'}) do
 for _, cfg in ipairs(require('dap.' .. lang).configurations) do
  for _, cmd in ipairs(cfg.initCommands or {}) do assert(not cmd:find('command script import')) end
 end
end
local cmds = require('dap.zig').configurations[1].initCommands
assert(vim.tbl_contains(cmds, 'settings set target.inline-breakpoint-strategy always'))
""")

    def test_helpers_with_spaces_are_home_relative_and_lldb_quoted(self):
        self.file("peter-projects/rust-prettifier-for-lldb/rust_prettifier_for_lldb.py")
        self.file("tools/zig/lldb_pretty_printers.py")
        self.lua("""
for _, lang in ipairs({'rust', 'zig'}) do
 local cmd = require('dap.' .. lang).configurations[1].initCommands[1]
 assert(cmd:find(vim.env.HOME, 1, true))
 assert(cmd:match('^command script import ".*"$'), cmd)
end
""")

    def test_compilers_use_argv_and_cancel_safely(self):
        self.lua("""
local calls, directories = {}, {}
vim.fn.system = function(argv) assert(type(argv) == 'table'); calls[#calls + 1] = argv; return '' end
vim.fn.mkdir = function(path, mode) assert(mode == 'p'); directories[#directories + 1] = path; return 1 end
vim.cmd('file source with spaces.rs')
assert(require('dap.rust').configurations[4].program():find('source with spaces', 1, true))
assert(calls[1][1] == 'rustc' and calls[1][6]:find('source with spaces', 1, true))
vim.cmd('file source with spaces.zig')
assert(require('dap.zig').configurations[2].program():find('source with spaces', 1, true))
assert(calls[2][1] == 'zig' and calls[2][3]:find('-femit-bin=', 1, true) == 1)
local n = #calls
for i = 3, 5 do assert(require('dap.zig').configurations[i].program() == require('dap').ABORT) end
assert(#calls == n)
""")

    def test_zig_multiple_projects_cancel_and_build_file_argv(self):
        self.file("first project/build.zig")
        self.file("second project/build.zig")
        self.lua("""
vim.fn.inputlist = function(choices) assert(#choices == 3); return 0 end
assert(require('dap.zig').configurations[3].program() == require('dap').ABORT)
vim.fn.inputlist = function() return 2 end
vim.fn.system = function(argv) assert(argv[#argv]:find('second project/build.zig', 1, true)); return '' end
assert(require('dap.zig').configurations[3].program():find('second project', 1, true))
""")

    def test_queries_are_regular_and_exact_custom_contents(self):
        for name, expected in QUERY_HASHES.items():
            path = CONFIG / "queries/mustache" / name
            self.assertFalse(path.is_symlink(), name)
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
        reef = CONFIG / "queries/reef/highlights.scm"
        self.assertFalse(reef.is_symlink())
        text = reef.read_text()
        self.assertIn("~/peter-projects/tree-sitter-reef/queries/highlights.scm", text)
        self.assertTrue(all(not line.strip() or line.startswith(";") for line in text.splitlines()))

    def test_markdown_corepack_build_needs_no_global_pnpm_shim(self):
        self.lua("""
local spec = require('plugins.markdown')[3]
assert(spec.build:find('mise --no-config exec node@24 -- corepack pnpm@12.3.4 install', 1, true))
assert(spec.build:find('MISE_AUTO_INSTALL=0', 1, true))
assert(spec.build:find('COREPACK_ENABLE_AUTO_PIN=0', 1, true))
assert(spec.build:find('COREPACK_ENABLE_PROJECT_SPEC=0', 1, true))
assert(spec.build:find('COREPACK_DEFAULT_TO_LATEST=0', 1, true))
assert(spec.build:find('--ignore-scripts', 1, true))
assert(spec.build:find('--config.minimumReleaseAge=10080', 1, true))
assert(spec.build:find('--config.minimumReleaseAgeStrict=true', 1, true))
assert(spec.build:find('--config.minimumReleaseAgeIgnoreMissingTime=false', 1, true))
assert(not spec.build:find('yarn', 1, true) and not spec.build:find('&& npm install', 1, true))
""")

    def test_all_lua_sources_parse_without_loading_plugins(self):
        paths = sorted(str(p.relative_to(CONFIG)) for p in (CONFIG / "lua").rglob("*.lua"))
        self.lua("for _, path in ipairs({" + ",".join(repr(p) for p in paths) + "}) do assert(loadfile(vim.env.XDG_CONFIG_HOME .. '/nvim/' .. path)) end")


class NvimDiscoveryTests(unittest.TestCase):
    def test_missing_bob_allows_discovery_and_reports_explicit_skips(self):
        with tempfile.TemporaryDirectory(prefix="nvim discovery ") as temporary:
            root = Path(temporary).resolve()
            copied = root / "checkout/dotfiles/tests/test_nvim_portability.py"
            copied.parent.mkdir(parents=True)
            shutil.copy2(__file__, copied)
            home = root / "empty home"
            home.mkdir()
            probe = """
import runpy, sys, unittest
namespace = runpy.run_path(sys.argv[1])
assert namespace['NVIM'] is None
result = unittest.TestResult()
unittest.defaultTestLoader.loadTestsFromTestCase(namespace['NvimPortabilityTests']).run(result)
assert result.testsRun > 0 and len(result.skipped) == result.testsRun
assert not result.errors and not result.failures
print('Editor tests explicitly skipped: no installed Bob Neovim')
"""
            result = subprocess.run([sys.executable, "-B", "-c", probe, str(copied)],
                                    env={"HOME": str(home), "PATH": "/usr/bin:/bin",
                                         "PYTHONDONTWRITEBYTECODE": "1"},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("explicitly skipped", result.stdout)

    def test_explicit_binary_does_not_require_bob_selection(self):
        with tempfile.TemporaryDirectory(prefix="nvim selection ") as temporary:
            root = Path(temporary).resolve()
            binary = root / "selected binary"
            binary.write_text("fixture executable, never run\n")
            binary.chmod(0o755)
            probe = "import runpy, sys; from pathlib import Path; assert runpy.run_path(sys.argv[1])['NVIM'] == Path(sys.argv[2])"
            result = subprocess.run([sys.executable, "-B", "-c", probe, __file__, str(binary)],
                                    env={"HOME": str(root), "PATH": "/usr/bin:/bin",
                                         "DOTFILES_TEST_NVIM": str(binary),
                                         "PYTHONDONTWRITEBYTECODE": "1"},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(0, result.returncode, result.stderr)


if __name__ == "__main__":
    unittest.main()
