"""Shell portability contracts; never source the live home or private includes."""
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HOME = Path(__file__).resolve().parents[2]
STARTUP = (".zshrc", ".zshenv", ".zprofile", ".zlogin", ".profile", ".bash_profile")
STUB = '''import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
if name == "mv":
    source, target = map(pathlib.Path, args[-2:])
    home = pathlib.Path(os.environ["HOME"])
    if source.parent != home or target.parent != home:
        sys.exit(99)
    os.replace(source, target); sys.exit(0)
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps([name, args]) + "\\n")
if name == "brew" and args == ["--prefix"]:
    print(os.environ["PREFIX"]); sys.exit(int(os.getenv("BREW_FAIL", "0")))
if name == "mise" and args == ["activate", "zsh"]:
    print('export FIXTURE_MISE=active'); sys.exit(0)
if name == "mise" and args[:2] == ["exec", "--"]:
    sys.exit(int(os.getenv("TOOL_STATUS", "0")))
if name == "pyenv" and args == ["init", "-"]:
    print('export FIXTURE_PYENV=active'); sys.exit(0)
if name == "fzf" and args == ["--zsh"]:
    print('export FIXTURE_FZF=active'); sys.exit(0)
if name == "kubectl" and args == ["completion", "zsh"]:
    print('export FIXTURE_KUBECTL=active'); sys.exit(0)
if name == "rvm":
    sys.exit(int(os.getenv("TOOL_STATUS", "0")))
if name == "git":
    if args in (["symbolic-ref", "--short", "HEAD"], ["branch", "--show-current"]):
        print(os.environ["FIXTURE_BRANCH"])
    sys.exit(0)
sys.exit(98)
'''


class ShellPortabilityTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="shell portability ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.home = self.root / "different user home"
        self.bin = self.root / "stub commands"
        self.home.mkdir()
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        self.env = {"HOME": str(self.home), "PATH": str(self.bin), "LOG": str(self.log),
                    "LC_ALL": "C", "TERM": "dumb", "PYTHONDONTWRITEBYTECODE": "1",
                    "PREFIX": str(self.root / "opt/homebrew")}
        for name in STARTUP:
            text = (HOME / name).read_text()
            # Remap fixed Brew roots even during RED; no live plugin/asdf code can load.
            text = text.replace("/opt/homebrew", str(self.root / "opt/homebrew"))
            text = text.replace("/usr/local", str(self.root / "usr/local"))
            # The legacy files have absolute source operands. Neutralize them before RED.
            text = text.replace('"/Users/peterbull/.deno/env"', '"$HOME/.deno/env"')
            text = text.replace('"/Users/peterbull/.bun/_bun"', '"$HOME/.bun/_bun"')
            # Signing is checked structurally, not activated in the fixture.
            text = re.sub(r'^export SSH_AUTH_SOCK=.*$', '', text, flags=re.M)
            (self.home / name).write_text(text)
        self.shim = self.home / "bin/rvm"
        self.shim.parent.mkdir()
        shutil.copy2(HOME / "bin/rvm", self.shim)
        self.shim.write_text(self.shim.read_text().replace("/Users/peterbull/.rvm/bin/rvm",
                                                        str(self.root / "legacy-home/.rvm/bin/rvm")))
        self.tool("bash", link="/bin/bash")
        self.tool("mv")

    def tool(self, name, directory=None, link=None):
        path = (directory or self.bin) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if link:
            path.symlink_to(link)
        else:
            path.write_text("#!" + sys.executable + "\n" + STUB)
            path.chmod(0o755)
        return path

    def run_shell(self, shell="/bin/zsh", code=None, status=0):
        code = code or '. "$HOME/.zshrc"; print -r -- "FIXTURE_PATH=$PATH"; print -r -- "FIXTURE_PNPM=$PNPM_HOME"; alias tmux-worktreeizer'
        result = subprocess.run(["/usr/bin/env", "-i", *[f"{k}={v}" for k, v in self.env.items()],
                                 shell, "-f", "-c", code], cwd=self.home, capture_output=True,
                                text=True, timeout=15)
        self.assertEqual(status, result.returncode, result.stderr)
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def fixture_source(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body + "\n")

    def brew(self, layout, on_path=True):
        prefix = self.root / layout
        self.env["PREFIX"] = str(prefix)
        self.tool("brew", directory=self.bin if on_path else prefix / "bin")
        for relative, marker in (("share/powerlevel10k/powerlevel10k.zsh-theme", "P10K"),
                                 ("share/zsh-autosuggestions/zsh-autosuggestions.zsh", "SUGGEST"),
                                 ("share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh", "SYNTAX")):
            self.fixture_source(prefix / relative, f'print -r -- FIXTURE_{marker}')
        for version in ("15", "16"):
            (prefix / f"opt/postgresql@{version}/bin").mkdir(parents=True)
        return prefix

    def test_missing_optional_dependencies_start_cleanly(self):
        result = self.run_shell()
        self.assertEqual("", result.stderr)
        self.assertEqual([], self.calls())

    def test_brew_prefixes_resolve_once_and_load_optional_plugins(self):
        for layout in ("opt/homebrew", "usr/local"):
            with self.subTest(layout=layout):
                prefix = self.brew(layout)
                if self.log.exists():
                    self.log.unlink()
                result = self.run_shell()
                self.assertEqual("", result.stderr)
                self.assertEqual([["brew", ["--prefix"]]], self.calls())
                for marker in ("P10K", "SUGGEST", "SYNTAX"):
                    self.assertIn("FIXTURE_" + marker, result.stdout)
                for version in ("15", "16"):
                    self.assertIn(str(prefix / f"opt/postgresql@{version}/bin"), result.stdout)

    def test_brew_executable_fallbacks(self):
        for layout in ("opt/homebrew", "usr/local"):
            with self.subTest(layout=layout):
                # One fallback is present at a time; no actual Brew roots are consulted.
                prefix = self.brew(layout, on_path=False)
                if self.log.exists():
                    self.log.unlink()
                result = self.run_shell()
                self.assertEqual("", result.stderr)
                self.assertEqual([["brew", ["--prefix"]]], self.calls())
                self.assertIn("FIXTURE_P10K", result.stdout)
                (prefix / "bin/brew").unlink()

    def test_brew_fallback_exports_tool_paths_without_duplicates(self):
        for layout in ("opt/homebrew", "usr/local"):
            with self.subTest(layout=layout):
                prefix = self.brew(layout, on_path=False)
                (prefix / "sbin").mkdir()
                self.tool("mise", directory=prefix / "bin")
                for initial_path in (str(self.bin), f"{prefix}/bin:{prefix}/sbin:{self.bin}"):
                    self.env["PATH"] = initial_path
                    if self.log.exists():
                        self.log.unlink()
                    result = self.run_shell()
                    self.assertEqual("", result.stderr)
                    path = next(line.removeprefix("FIXTURE_PATH=").split(":")
                                for line in result.stdout.splitlines()
                                if line.startswith("FIXTURE_PATH="))
                    self.assertEqual(1, path.count(str(prefix / "bin")))
                    self.assertEqual(1, path.count(str(prefix / "sbin")))
                    self.assertEqual(1, self.calls().count(["mise", ["activate", "zsh"]]))
                (prefix / "bin/brew").unlink()

    def test_failed_brew_prefix_does_not_load_plugins(self):
        self.brew("opt/homebrew")
        self.env["BREW_FAIL"] = "9"
        result = self.run_shell()
        self.assertEqual("", result.stderr)
        self.assertNotIn("FIXTURE_P10K", result.stdout)
        self.assertEqual([["brew", ["--prefix"]]], self.calls())

    def test_one_mise_activation_before_work_include_and_home_bin_precedence(self):
        self.tool("mise")
        self.tool("nvm")
        self.tool("rvm", directory=self.home / ".rvm/bin")
        self.fixture_source(self.home / "work/ctm-dev/ctm.shell",
                            '[[ "$FIXTURE_MISE" == active ]] || return 70; print FIXTURE_CTM')
        result = self.run_shell()
        self.assertEqual("", result.stderr)
        self.assertIn("FIXTURE_CTM", result.stdout)
        self.assertEqual([["mise", ["activate", "zsh"]]], self.calls())
        path = next(line.removeprefix("FIXTURE_PATH=") for line in result.stdout.splitlines()
                    if line.startswith("FIXTURE_PATH="))
        self.assertLess(path.split(":").index(str(self.home / "bin")),
                        path.split(":").index(str(self.home / ".rvm/bin")))

    def test_home_paths_with_spaces_and_retained_tool_owners(self):
        result = self.run_shell()
        path = next(line.removeprefix("FIXTURE_PATH=") for line in result.stdout.splitlines()
                    if line.startswith("FIXTURE_PATH="))
        for relative in ("Library/pnpm/bin", ".local/bin", ".lmstudio/bin", ".bend/bin",
                         ".bun/bin", ".local/share/bob/nvim-bin", ".zvm/bin", ".zvm/self",
                         "go/bin", ".luarocks/bin", "bin"):
            self.assertIn(str(self.home / relative), path.split(":"))
        self.assertIn("FIXTURE_PNPM=" + str(self.home / "Library/pnpm"), result.stdout)
        self.assertNotIn("/Users/peterbull", path)
        self.assertNotIn("opt/ruby", path)
        self.assertNotIn("opt/python", path)
        self.assertNotIn("opt/postgresql", path)

    def test_optional_completion_pyenv_omz_and_prompt(self):
        for name in ("fzf", "kubectl", "terraform", "pyenv"):
            self.tool(name)
        self.fixture_source(self.home / ".oh-my-zsh/oh-my-zsh.sh", 'print FIXTURE_OMZ')
        self.fixture_source(self.home / ".p10k.zsh", 'print FIXTURE_PROMPT')
        result = self.run_shell(code='. "$HOME/.zshrc"; print "$FIXTURE_PYENV $FIXTURE_FZF $FIXTURE_KUBECTL"; whence -w terraform')
        self.assertEqual("", result.stderr)
        self.assertIn("FIXTURE_OMZ", result.stdout)
        self.assertIn("FIXTURE_PROMPT", result.stdout)
        self.assertIn("active active active", result.stdout)
        self.assertEqual(sorted([["fzf", ["--zsh"]], ["kubectl", ["completion", "zsh"]],
                                 ["pyenv", ["init", "-"]]]), sorted(self.calls()))

    def test_local_includes_optional_and_ordered(self):
        self.fixture_source(self.home / ".config/zsh/work.local.zsh", 'print FIXTURE_WORK_LOCAL')
        self.fixture_source(self.home / ".zshrc.local", 'print FIXTURE_LOCAL')
        result = self.run_shell()
        self.assertEqual("", result.stderr)
        self.assertIn("FIXTURE_WORK_LOCAL", result.stdout)
        self.assertIn("FIXTURE_LOCAL", result.stdout)
        self.assertLess(result.stdout.index("FIXTURE_WORK_LOCAL"), result.stdout.index("FIXTURE_LOCAL"))

    def test_login_files_missing_dependencies(self):
        for name, shell in ((".zshenv", "/bin/zsh"), (".zprofile", "/bin/zsh"),
                            (".zlogin", "/bin/zsh"), (".profile", "/bin/sh"),
                            (".bash_profile", "/bin/bash")):
            with self.subTest(name=name):
                result = self.run_shell(shell, f'. "$HOME/{name}"')
                self.assertEqual("", result.stderr)
        self.assertEqual([], self.calls())

    def test_bash_profile_cargo_deno_once_and_no_rvm_activation(self):
        self.fixture_source(self.home / ".cargo/env", 'printf "FIXTURE_CARGO\\n"')
        self.fixture_source(self.home / ".deno/env", 'printf "FIXTURE_DENO\\n"')
        self.fixture_source(self.home / ".rvm/scripts/rvm", 'printf "UNWANTED_RVM\\n"')
        result = self.run_shell("/bin/bash", '. "$HOME/.bash_profile"; printf "%s\\n" "$PATH"')
        self.assertEqual("", result.stderr)
        self.assertEqual(1, result.stdout.count("FIXTURE_CARGO"))
        self.assertEqual(1, result.stdout.count("FIXTURE_DENO"))
        self.assertNotIn("UNWANTED_RVM", result.stdout)
        self.assertIn(str(self.home / ".docker/bin"), result.stdout)
        self.assertNotIn("/Users/peterbull", result.stdout)

    def test_zsh_login_keeps_cargo_and_omits_asdf_rvm(self):
        self.fixture_source(self.home / ".cargo/env", 'print FIXTURE_CARGO')
        self.fixture_source(self.root / "opt/homebrew/opt/asdf/libexec/asdf.sh", 'print UNWANTED_ASDF')
        self.fixture_source(self.home / ".rvm/scripts/rvm", 'print UNWANTED_RVM')
        result = self.run_shell(code='. "$HOME/.zshenv"; . "$HOME/.zprofile"; . "$HOME/.zlogin"; print "$PATH"')
        self.assertEqual("", result.stderr)
        self.assertEqual(1, result.stdout.count("FIXTURE_CARGO"))
        self.assertNotIn("UNWANTED_", result.stdout)
        self.assertIn(str(self.home / ".docker/bin"), result.stdout)

    def test_dynamic_worktreeizer_bash_and_fallback(self):
        result = self.run_shell()
        self.assertIn('tmux-worktreeizer=', result.stdout)
        self.assertIn('bash', result.stdout)
        self.assertNotIn('/opt/homebrew/bin/bash', result.stdout)
        prefix = self.brew("usr/local")
        self.tool("bash", directory=prefix / "bin", link="/bin/bash")
        result = self.run_shell()
        self.assertIn(str(prefix / "bin/bash"), result.stdout)

    def run_shim(self, *args, status=0):
        result = subprocess.run(["/usr/bin/env", "-i", *[f"{k}={v}" for k, v in self.env.items()],
                                 str(self.shim), *args], cwd=self.home, text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(status, result.returncode, result.stderr)
        return result

    def test_shim_mise_preserves_argv_and_exit_status(self):
        self.tool("mise")
        self.env["TOOL_STATUS"] = "37"
        self.run_shim("3.4.9", "do", "bundle", "exec", "command with spaces", "*", "", status=37)
        self.assertEqual([["mise", ["exec", "--", "bundle", "exec", "command with spaces", "*", ""]]], self.calls())

    def test_shim_admin_fallback_is_home_relative_and_preserves_argv(self):
        self.tool("rvm", directory=self.home / ".rvm/bin")
        self.env["TOOL_STATUS"] = "39"
        self.run_shim("list", "argument with spaces", status=39)
        self.assertEqual([["rvm", ["list", "argument with spaces"]]], self.calls())

    def test_shim_missing_admin_fallback_is_explicit(self):
        result = self.run_shim("list", status=127)
        self.assertIn("RVM is not installed", result.stderr)
        self.assertEqual([], self.calls())

    def test_shim_missing_mise_reports_failure(self):
        result = self.run_shim(".", "do", "bundle", "exec", status=127)
        self.assertIn("mise", result.stderr)

    def test_syntax(self):
        for name in STARTUP:
            shells = ("/bin/sh", "/bin/bash") if name == ".profile" else (
                "/bin/bash",) if name == ".bash_profile" else ("/bin/zsh",)
            for shell in shells:
                result = subprocess.run([shell, "-n", str(HOME / name)], capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stderr)
        result = subprocess.run(["/bin/bash", "-n", str(HOME / "bin/rvm")], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)

    def test_preservation_contract_without_git_history(self):
        fixture = (self.home / ".zshrc").read_text()
        self.fixture_source(self.home / ".zshrc", fixture + '\nexport SSH_AUTH_SOCK="$HOME/fixture-agent.sock"')
        with mock.patch(__name__ + ".HOME", self.home):
            self.test_private_includes_signing_and_functions_preserved()

    def test_private_includes_signing_and_functions_preserved(self):
        current = (HOME / ".zshrc").read_text()
        self.assertEqual(1, len(re.findall(r'^export SSH_AUTH_SOCK=', current, re.M)))
        include_block = 'if [ -f ~/.secrets ]; then\n    source ~/.secrets\nfi'
        self.assertTrue(include_block in current, "Missing guarded secrets include")
        work_include = '[ -f "$HOME/work/ctm-dev/ctm.shell" ] && . "$HOME/work/ctm-dev/ctm.shell"'
        self.assertTrue(work_include in current, "Missing guarded CTM include")
        functions = set(re.findall(r'^([\w-]+)\(\)\s*\{', current, re.M))
        for name in ("gpf", "gsarchive", "grepdiff", "dirdump_flat", "dirdump_all",
                     "create_issue_checkout_branch", "clipdump", "rig_models",
                     "model-config", "tmux-log", "git"):
            self.assertIn(name, functions)
        aliases = set(re.findall(r'^alias ([\w-]+)=', current, re.M))
        for name in ("dup", "ddown", "dlog", "dbuild", "n", "nc", "nz", "nd", "np", "c",
                     "va", "cb", "cr", "crf", "ca", "caf", "zb", "gpc", "gpm", "gpc-telus",
                     "gs-apply", "ghs", "gsa", "ghc", "zr", "tf", "t1", "t2", "t3", "t4",
                     "clp", "models", "lg", "work", "peter", "python", "lzd", "kfwd", "pib",
                     "ctmstart", "ctmstop", "tr", "tmux-log-stop", "chrome-debug"):
            self.assertIn(name, aliases)

    def test_git_safeguards_with_stubbed_git(self):
        self.tool("git")
        cases = (("main", "gpf", 1, ["branch", "--show-current"]),
                 ("master", "gpf", 1, ["branch", "--show-current"]),
                 ("master", "git commit -m fixture", 1, ["symbolic-ref", "--short", "HEAD"]),
                 ("master", "git push", 1, ["symbolic-ref", "--short", "HEAD"]),
                 ("feature", "git push origin master", 1, None),
                 ("feature", "git commit -m fixture", 0, ["commit", "-m", "fixture"]),
                 ("feature", "git push origin feature", 0, ["push", "origin", "feature"]),
                 ("feature", "gpf", 0, ["push", "-u", "origin", "feature", "--force-with-lease"]))
        for branch, operation, status, last_argv in cases:
            with self.subTest(branch=branch, operation=operation):
                if self.log.exists():
                    self.log.unlink()
                self.env["FIXTURE_BRANCH"] = branch
                result = self.run_shell(code='. "$HOME/.zshrc"; ' + operation +
                                        '; result=$?; print -r -- "FIXTURE_RESULT=$result"')
                self.assertEqual("", result.stderr)
                self.assertIn(f"FIXTURE_RESULT={status}", result.stdout)
                calls = self.calls()
                if last_argv is None:
                    self.assertEqual([], calls)
                else:
                    self.assertEqual(["git", last_argv], calls[-1])
                if status:
                    self.assertFalse(any(argv[0] in ("push", "commit") for _, argv in calls))

    def test_private_includes_use_only_synthetic_fixtures(self):
        self.fixture_source(self.home / ".secrets", 'print FIXTURE_PRIVATE_INCLUDE')
        self.fixture_source(self.home / "work/ctm-dev/ctm.shell", 'print FIXTURE_WORK_INCLUDE')
        result = self.run_shell()
        self.assertEqual("", result.stderr)
        self.assertEqual(1, result.stdout.count("FIXTURE_PRIVATE_INCLUDE"))
        self.assertEqual(1, result.stdout.count("FIXTURE_WORK_INCLUDE"))

    def test_no_competing_startup_owners_or_fixed_home_paths(self):
        rc = (HOME / ".zshrc").read_text()
        self.assertEqual(1, rc.count("mise activate zsh"))
        self.assertNotRegex(rc, r"(?im)^.*(?:nvm\.sh|nvm alias|NVM_DIR|nvm bash_completion).*$")
        for name in STARTUP:
            text = (HOME / name).read_text()
            text = re.sub(r'^export SSH_AUTH_SOCK=.*$', '', text, flags=re.M)
            self.assertNotIn("/Users/peterbull", text)
            self.assertNotIn(".rvm/scripts/rvm", text)
            self.assertNotIn("asdf.sh", text)
        result = subprocess.run(["/usr/bin/git", "-C", str(HOME), "check-ignore", "--no-index",
                                 ".config/zsh/work.local.zsh", ".zshrc.local"], capture_output=True, text=True)
        self.assertEqual(0, result.returncode)
        self.assertEqual([".config/zsh/work.local.zsh", ".zshrc.local"], result.stdout.splitlines())


if __name__ == "__main__":
    unittest.main()
