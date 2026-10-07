"""Disposable fake commands only: /usr/bin/python3 -B -m unittest discover -s dotfiles/tests."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "dotfiles/scripts/provision-optional"
STUB = r'''import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
def swap(path, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists(): path.rename(path.with_name(path.name + '.preserved'))
    if mode == 'symlink': path.symlink_to(os.environ['PREFIX'])
    else: path.mkdir(); (path / '.git').mkdir()
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps([name, args, dict(os.environ, FIXTURE_CWD=os.getcwd())]) + "\n")
if name == "uname": print(os.getenv("PLATFORM", "Darwin")); sys.exit(0)
if name == "xcode-select": sys.exit(int(os.getenv("CLT_FAIL", "0")))
if name == "brew" and args == ["--prefix"]: print(os.environ["PREFIX"]); sys.exit(0)
if name == "mise" and args == ["where", "node@24"]:
    print(os.environ["NODE_PREFIX"]); sys.exit(int(os.getenv("NODE_FAIL", "0")))
if name == "git" and "-C" in args:
    if args[-2:] == ["rev-parse", "--show-toplevel"]: print(args[1])
    elif args[-2:] == ["rev-parse", "HEAD"]: print(os.getenv("REV", "0" * 40))
    elif args[-3:] == ["status", "--porcelain", "--untracked-files=all"]: print(os.getenv("DIRTY", ""))
    elif "checkout" in args:
        pathlib.Path(args[1], "checked-out").write_text(args[-1])
        sys.exit(int(os.getenv("CHECKOUT_FAIL", "0")))
    else: sys.exit(93)
    sys.exit(int(os.getenv("GIT_INSPECT_FAIL", "0")))
if name == "git" and args[:2] == ["clone", "--no-checkout"]:
    dest = pathlib.Path(args[-1]); dest.mkdir(exist_ok=True); (dest / ".git").mkdir()
    (dest / "partial-clone").write_text("preserve me")
    if os.getenv('CLONE_SWAP'): swap(dest, os.environ['CLONE_SWAP'])
    if os.getenv('CLONE_GIT_SWAP'): swap(dest / '.git', 'symlink')
    if os.getenv('AFTER_CLONE_SWAP'): swap(pathlib.Path(os.environ['HOME']) / os.environ['AFTER_CLONE_SWAP'], os.getenv('SWAP_MODE', 'symlink'))
    sys.exit(int(os.getenv("CLONE_FAIL", "0")))
if name == "uv" and args[0] == "venv":
    dest = pathlib.Path(args[-1]); dest.mkdir(exist_ok=True); (dest / "bin").mkdir()
    (dest / "bin/python3").write_text("not executed")
    (dest / "bin/python3").chmod(0o755)
    (dest / "pyvenv.cfg").write_text("version = 3.12.13\ninclude-system-site-packages = false\n")
    if os.getenv('FIXTURE_UV_SWAP'): swap(pathlib.Path(os.environ['HOME']) / os.environ['FIXTURE_UV_SWAP'], os.getenv('SWAP_MODE', 'symlink'))
    if os.getenv('FIXTURE_PYTHON_REDIRECT'):
        (dest / 'bin/python3').unlink()
        (dest / 'bin/python3').symlink_to(os.environ['FIXTURE_PYTHON_REDIRECT'])
if name == "uv" and args[:2] == ["pip", "install"]:
    dest = pathlib.Path(args[3]).parents[1]
    metadata = dest / "lib/python3.12/site-packages/pynvim-0.6.0.dist-info/METADATA"
    metadata.parent.mkdir(parents=True)
    metadata.write_text("Name: pynvim\nVersion: 0.6.0\n")
if name == 'mise' and 'install' in args and os.getenv('RUNTIME_SWAP'):
    swap(pathlib.Path(os.environ['HOME']) / os.environ['RUNTIME_SWAP'], os.getenv('SWAP_MODE', 'symlink'))
if name == 'mise' and 'install' in args and os.getenv('FIXTURE_RUNTIME_CONFIG_CREATE'):
    config = pathlib.Path(os.environ.get('BOB_CONFIG', str(pathlib.Path(os.environ['HOME']) / '.local/state/dotfiles-bob/config.json')))
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text('{"unapproved": true}')
if name == 'bob' and args[0] == 'install' and os.getenv('FIXTURE_BOB_CONFIG_SWAP'):
    config = pathlib.Path(os.environ.get('BOB_CONFIG', str(pathlib.Path(os.environ['HOME']) / '.config/bob/config.json')))
    swap(config, 'symlink')
if name == 'bob' and args[0] == 'install' and os.getenv('FIXTURE_BOB_LEAF_SWAP'):
    swap(pathlib.Path(os.environ['HOME']) / os.environ['FIXTURE_BOB_LEAF_SWAP'], 'symlink')
if name == 'bob' and args[0] == os.getenv('FIXTURE_BOB_CREATE_STAGE'):
    for relative in ('.local/share/bob/used', '.local/share/bob/nvim-bin/nvim'):
        path = pathlib.Path(os.environ['HOME']) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('fixture Bob output')
if name in ("uv", "mise", "bob", "brew"):
    sys.exit(int(os.getenv("FIXTURE_" + name.upper() + "_FAIL", "0")))
sys.exit(94)
'''


class ProvisionOptionalTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SOURCE.is_file(), "RED: provision-optional is not implemented")
        temp = tempfile.TemporaryDirectory(prefix="optional fixture ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.home, self.repo, self.bin = [self.root / p for p in ("fake home", "fake repo", "fake bin")]
        for directory in (self.home, self.repo, self.bin):
            directory.mkdir()
        for name in ("dotfiles/scripts/provision-optional", "dotfiles/provisioning.json",
                     "dotfiles/pnpm-workspace.yaml", "Brewfile.work"):
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        self.script = self.repo / "dotfiles/scripts/provision-optional"
        self.log = self.root / "calls.jsonl"
        self.env = {"PATH": str(self.bin), "HOME": str(self.home), "LOG": str(self.log),
                    "PREFIX": str(self.root), "NODE_PREFIX": str(self.home / ".local/share/mise/installs/node/24.16.0"),
                    "PYTHONDONTWRITEBYTECODE": "1", "LC_ALL": "C"}
        node_bin = Path(self.env["NODE_PREFIX"]) / "bin"
        node_bin.mkdir(parents=True)
        for name in ("node", "corepack"):
            (node_bin / name).write_text("not executed")
            (node_bin / name).chmod(0o755)
        for name in ("git", "uv", "mise", "bob", "brew", "uname", "xcode-select"):
            path = self.bin / name
            path.write_text("#!" + sys.executable + "\n" + STUB)
            path.chmod(0o755)
        for name in (".npmrc", ".zshrc", ".env"):
            (self.home / name).write_text("PRIVATE_SECRET_DO_NOT_READ_OR_CHANGE")
        self.manifest = json.loads((self.repo / "dotfiles/provisioning.json").read_text())

    def snapshot(self):
        return {str(p.relative_to(self.root)): (p.lstat().st_mode,
                os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
                for p in self.root.rglob("*") if p != self.log}

    def run_cli(self, *args, code=0, readonly=False):
        self.log.unlink(missing_ok=True)
        before = self.snapshot()
        result = subprocess.run([sys.executable, "-B", str(self.script), *args], env=self.env,
                                cwd=self.root, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(code, result.returncode, output)
        self.assertNotIn("PRIVATE_SECRET", output)
        if readonly:
            self.assertEqual(before, self.snapshot())
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return output, calls

    def existing_repo(self, name="oh-my-zsh"):
        item = next(r for r in self.manifest["repos"] if r["name"] == name)
        dest = self.home / item["path"]
        dest.mkdir(parents=True)
        (dest / ".git").mkdir()
        (dest / "untracked module.py").write_text("essential customization")
        return dest

    def test_default_preview_zero_mutations(self):
        output, calls = self.run_cli(readonly=True)
        self.assertIn("Preview", output)
        for feature in ("shell", "tmux", "provider", "editor", "runtimes", "node-tools", "work"):
            self.assertIn(feature, output)
        self.assertFalse(any(c[1][:2] in (["clone", "--no-checkout"], ["bundle", "install"])
                             or c[0] in ("uv", "bob") for c in calls))

    def test_closed_cli_requires_explicit_apply_selection(self):
        for args in (("--apply",), ("--feature", "https://evil.invalid/x.git"),
                     ("--source", "anything"), ("--feature", "reef")):
            self.run_cli(*args, code=2, readonly=True)

    def test_fresh_clone_uses_manifest_full_pins_and_no_tpm_execution(self):
        _, calls = self.run_cli("--apply", "--feature", "tmux")
        for item in self.manifest["repos"]:
            if item["feature"] == "tmux":
                dest = str(self.home / item["path"])
                self.assertIn(["git", ["clone", "--no-checkout", "--", item["url"], dest]],
                              [c[:2] for c in calls])
                self.assertIn(["git", ["-C", dest, "checkout", "--detach", item["sha"]]],
                              [c[:2] for c in calls])
        self.assertEqual({"git"}, {c[0] for c in calls})

    def test_dirty_existing_repos_are_preserved_even_if_revision_differs(self):
        self.existing_repo()
        self.env["DIRTY"] = "?? untracked module.py"
        output, calls = self.run_cli("--apply", "--feature", "shell", readonly=True)
        self.assertIn("dirty/untracked state unverified", output.lower())
        self.assertNotIn("Dirty checkout preserved", output)
        self.assertFalse(any("status" in c[1] for c in calls))
        self.assertIn("revision", output.lower())
        self.assertFalse(any("clone" in c[1] or "checkout" in c[1] for c in calls))

    def test_git_inspection_failure_preserves_existing_destination(self):
        self.existing_repo()
        self.env["GIT_INSPECT_FAIL"] = "17"
        self.run_cli("--apply", "--feature", "shell", code=1, readonly=True)

    def test_all_selected_features_preflight_before_any_install(self):
        (self.bin / "bob").unlink()
        (self.home / ".virtualenvs/nvim").mkdir(parents=True)
        output, calls = self.run_cli("--apply", "--feature", "tmux", "--feature", "provider",
                                    "--feature", "runtimes", code=1, readonly=True)
        self.assertIn("bob", output)
        self.assertIn("owned", output.lower())
        self.assertFalse(any("clone" in c[1] or c[0] in ("mise", "uv") for c in calls))

    def test_noncanonical_or_invalid_home_is_refused(self):
        for home in ("relative", str(self.root / "absent"), str(self.home) + "/../fake home"):
            with self.subTest(home=home):
                self.env["HOME"] = home
                self.run_cli("--apply", "--feature", "tmux", code=1, readonly=True)
        link = self.root / "home link"
        link.symlink_to(self.home)
        self.env["HOME"] = str(link)
        self.run_cli("--apply", "--feature", "tmux", code=1, readonly=True)

    def test_symlinked_ancestors_leaf_and_special_files_refused(self):
        cases = ("ancestor", "leaf", "fifo", "unexpected-directory")
        for case in cases:
            with self.subTest(case=case):
                temp = tempfile.TemporaryDirectory(dir=self.root)
                self.addCleanup(temp.cleanup)
                self.home = Path(temp.name).resolve()
                self.env["HOME"] = str(self.home)
                target = self.home / ".tmux/plugins/tpm"
                if case == "ancestor":
                    (self.home / ".tmux").symlink_to(self.root)
                else:
                    target.parent.mkdir(parents=True)
                    if case == "leaf":
                        target.symlink_to(self.root)
                    elif case == "fifo":
                        os.mkfifo(target)
                    else:
                        target.mkdir()
                self.run_cli("--apply", "--feature", "tmux", code=1, readonly=True)

    def test_invalid_manifest_keys_urls_pins_and_paths_refused(self):
        manifest_path = self.repo / "dotfiles/provisioning.json"
        for key, value in (("url", "https://user:secret@github.com/tmux-plugins/tpm.git"),
                           ("url", "https://github.com/unknown/random.git"),
                           ("sha", "main"), ("path", "../escape"),
                           ("path", str(self.root / "escape")), ("path", ".tmux/../escape"),
                           ("feature", "arbitrary"), ("unexpected", "value")):
            with self.subTest(key=key, value=value):
                data = json.loads(json.dumps(self.manifest))
                data["repos"][1][key] = value
                manifest_path.write_text(json.dumps(data))
                self.run_cli("--apply", "--feature", "shell", code=1, readonly=True)

    def test_clone_failure_preserves_partial_state_and_propagates_status(self):
        self.env["CLONE_FAIL"] = "23"
        output, calls = self.run_cli("--apply", "--feature", "tmux", code=23)
        self.assertTrue((self.home / ".tmux/plugins/tpm/partial-clone").is_file())
        self.assertIn("preserved", output.lower())
        self.assertFalse(any("checkout" in c[1] for c in calls))
        self.assertFalse((self.home / ".tmux/plugins/tmux-sensible").exists())

    def test_checkout_failure_preserves_clone(self):
        self.env["CHECKOUT_FAIL"] = "24"
        self.run_cli("--apply", "--feature", "tmux", code=24)
        self.assertTrue((self.home / ".tmux/plugins/tpm/partial-clone").exists())

    def test_provider_pinned_uv_commands_and_owned_repeat_is_noop(self):
        _, calls = self.run_cli("--apply", "--feature", "provider")
        dest = self.home / ".virtualenvs/nvim"
        self.assertEqual([["uv", ["venv", "--python", "3.12.13", str(dest)]],
                          ["uv", ["pip", "install", "--python", str(dest / "bin/python3"),
                                  "pynvim==0.6.0"]]], [c[:2] for c in calls])
        self.assertTrue((dest / ".dotfiles-provider.json").is_file())
        _, calls = self.run_cli("--apply", "--feature", "provider", readonly=True)
        self.assertEqual([], calls)

    def test_uv_version_info_metadata_is_accepted_for_owned_env(self):
        self.run_cli("--apply", "--feature", "provider")
        config = self.home / ".virtualenvs/nvim/pyvenv.cfg"
        config.write_text("version_info = 3.12.13\ninclude-system-site-packages = false\n")
        self.run_cli("--apply", "--feature", "provider", readonly=True)

    def test_provider_marker_and_package_symlinks_are_refused(self):
        self.run_cli("--apply", "--feature", "provider")
        dest = self.home / ".virtualenvs/nvim"
        metadata = dest / "lib/python3.12/site-packages/pynvim-0.6.0.dist-info/METADATA"
        saved = self.root / "saved metadata"
        saved.write_bytes(metadata.read_bytes())
        metadata.unlink()
        metadata.symlink_to(saved)
        self.run_cli("--apply", "--feature", "provider", code=1, readonly=True)

    def test_redirected_cache_and_runtime_paths_are_refused_before_installs(self):
        for feature, relative in (("provider", ".cache/uv"), ("node-tools", "Library/pnpm/bin"),
                                  ("runtimes", ".local/share/bob")):
            target = self.home / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(self.root)
            self.run_cli("--apply", "--feature", "tmux", "--feature", feature, code=1, readonly=True)
            target.unlink()

    def test_provider_user_env_and_fake_marker_refused(self):
        dest = self.home / ".virtualenvs/nvim"
        dest.mkdir(parents=True)
        self.run_cli("--apply", "--feature", "provider", code=1, readonly=True)
        (dest / ".dotfiles-provider.json").write_text('{"owner":"dotfiles/provision-optional"}')
        self.run_cli("--apply", "--feature", "provider", code=1, readonly=True)

    def test_provider_failure_leaves_unowned_partial_env(self):
        self.env["FIXTURE_UV_FAIL"] = "32"
        self.run_cli("--apply", "--feature", "provider", code=32)
        self.assertTrue((self.home / ".virtualenvs/nvim").exists())
        self.assertFalse((self.home / ".virtualenvs/nvim/.dotfiles-provider.json").exists())
        self.env.pop("FIXTURE_UV_FAIL")
        self.run_cli("--apply", "--feature", "provider", code=1, readonly=True)

    def test_runtime_commands_do_not_rewrite_global_configuration(self):
        _, calls = self.run_cli("--apply", "--feature", "runtimes")
        self.assertEqual([["mise", ["--no-config", "install", "node@24", "ruby@3.4.9"]],
                          ["bob", ["install", "0.11.7"]], ["bob", ["use", "0.11.7"]]],
                         [c[:2] for c in calls])
        self.assertFalse((self.home / ".config/mise/config.toml").exists())

    def test_work_bundle_cleanup_disabled_and_failure_status_propagated(self):
        self.env.update({"HOMEBREW_BUNDLE_INSTALL_CLEANUP": "1",
                         "HOMEBREW_BUNDLE_FORCE_INSTALL_CLEANUP": "1", "FIXTURE_BREW_FAIL": "34"})
        _, calls = self.run_cli("--apply", "--feature", "work", code=34, readonly=True)
        tool, args, env = calls[-1]
        self.assertEqual("brew", tool)
        self.assertEqual(["bundle", "install", "--no-upgrade", "--file=" + str(self.repo / "Brewfile.work")], args)
        for name in ("HOMEBREW_NO_AUTO_UPDATE", "HOMEBREW_NO_ANALYTICS", "HOMEBREW_NO_INSTALL_CLEANUP"):
            self.assertEqual("1", env[name])
        self.assertNotIn("HOMEBREW_BUNDLE_INSTALL_CLEANUP", env)
        self.assertNotIn("HOMEBREW_BUNDLE_FORCE_INSTALL_CLEANUP", env)

    def test_work_clt_and_platform_preflight_blocks_all_features(self):
        for changes in ({"CLT_FAIL": "1"}, {"PLATFORM": "Linux"}, {"PREFIX": ""}):
            original = self.env.copy()
            self.env.update(changes)
            self.run_cli("--apply", "--feature", "work", "--feature", "tmux", code=1, readonly=True)
            self.env = original

    def test_node_tools_pinned_managed_node_global_bin_and_supply_chain_delay(self):
        _, calls = self.run_cli("--apply", "--feature", "node-tools")
        tool, args, env = calls[-1]
        self.assertEqual("mise", tool)
        self.assertEqual(["--no-config", "exec", "node@24.16.0", "--", "corepack", "pnpm@12.3.4", "add", "--global"], args[:8])
        self.assertIn("--global-bin-dir=" + str(self.home / "Library/pnpm/bin"), args)
        self.assertIn("--store-dir=" + str(self.home / "Library/pnpm/store"), args)
        self.assertIn("--config.cacheDir=" + str(self.home / "Library/Caches/dotfiles-pnpm"), args)
        self.assertIn("--config.stateDir=" + str(self.home / ".local/state/dotfiles-pnpm"), args)
        self.assertIn("--config.minimumReleaseAge=10080", args)
        self.assertIn("--config.minimumReleaseAgeStrict=true", args)
        self.assertIn("--config.minimumReleaseAgeIgnoreMissingTime=false", args)
        self.assertIn("--ignore-scripts", args)
        self.assertIn("@earendil-works/pi-coding-agent@1.0.4", args)
        self.assertIn("@usebruno/cli@4.0.0", args)
        self.assertEqual("/dev/null", env["NPM_CONFIG_USERCONFIG"])
        self.assertEqual("0", env["MISE_AUTO_INSTALL"])
        self.assertEqual("0", env["COREPACK_ENABLE_AUTO_PIN"])
        self.assertEqual("0", env["COREPACK_DEFAULT_TO_LATEST"])
        self.assertEqual(str(self.home / "Library/pnpm/bin"), env["PNPM_HOME"])
        self.assertEqual("minimumReleaseAge: 10080\nminimumReleaseAgeStrict: true\nminimumReleaseAgeIgnoreMissingTime: false\n",
                         (self.repo / "dotfiles/pnpm-workspace.yaml").read_text())

    def test_node_store_cache_state_symlinks_refuse_all_selected_features(self):
        for relative in ("Library/pnpm/store", "Library/Caches/dotfiles-pnpm", ".local/state/dotfiles-pnpm"):
            with self.subTest(path=relative):
                target = self.home / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(self.root)
                self.run_cli("--apply", "--feature", "tmux", "--feature", "node-tools", code=1, readonly=True)
                target.unlink()

    def test_mise_apply_has_normalized_context_and_preview_executes_no_mise(self):
        self.env["MISE_DATA_DIR"] = str(self.root / "alternate mise")
        self.env["XDG_DATA_HOME"] = str(self.root / "alternate xdg")
        _, calls = self.run_cli("--feature", "node-tools", readonly=True)
        self.assertEqual([], calls)
        _, calls = self.run_cli("--apply", "--feature", "node-tools")
        self.assertEqual(1, len(calls))
        for _, _, env in calls:
            self.assertEqual(str(self.home / ".local/share/mise"), env["MISE_DATA_DIR"])
            self.assertEqual(str(self.home / ".local/share"), env["XDG_DATA_HOME"])
            self.assertEqual(str(self.repo / "dotfiles"), env["FIXTURE_CWD"])

    def test_node_tools_conflicting_pnpm_home_or_missing_managed_node_refused(self):
        for change in ({"PNPM_HOME": str(self.home / "wrong")},):
            original = self.env.copy()
            self.env.update(change)
            self.run_cli("--apply", "--feature", "node-tools", "--feature", "tmux", code=1, readonly=True)
            self.env = original

    def test_check_is_readonly_metadata_not_runtime_health(self):
        self.existing_repo()
        self.env["DIRTY"] = "?? required.py"
        output, calls = self.run_cli("--check", readonly=True)
        self.assertIn("WARN [optional]", output)
        self.assertIn("dirty/untracked state unverified", output.lower())
        self.assertFalse(any("status" in c[1] for c in calls))
        self.assertIn("runtime health", output.lower())
        self.assertEqual({"git"}, {c[0] for c in calls})

    def test_checkout_swapped_after_clone_refuses_checkout(self):
        for mode in ("symlink", "directory"):
            with self.subTest(mode=mode):
                self.home = self.root / ("clone home " + mode)
                self.home.mkdir()
                self.env.update(HOME=str(self.home), CLONE_SWAP=mode)
                output, calls = self.run_cli("--apply", "--feature", "shell", code=1)
                self.assertIn("preserved", output)
                self.assertFalse(any("checkout" in c[1] for c in calls))
                self.assertTrue((self.home / ".oh-my-zsh.preserved/partial-clone").exists())

    def test_clone_git_symlink_refuses_checkout(self):
        self.env["CLONE_GIT_SWAP"] = "1"
        _, calls = self.run_cli("--apply", "--feature", "shell", code=1)
        self.assertFalse(any("checkout" in c[1] for c in calls))

    def test_provider_caches_install_bin_lib_swaps_refuse_later_command(self):
        for index, relative in enumerate((".cache/uv", ".cache/uv-python", ".local/share/uv/python",
                                         ".virtualenvs/nvim/bin", ".virtualenvs/nvim/lib")):
            with self.subTest(path=relative):
                self.home = self.root / ("uv swap home " + str(index))
                self.home.mkdir()
                self.env.update(HOME=str(self.home), FIXTURE_UV_SWAP=relative)
                _, calls = self.run_cli("--apply", "--feature", "provider", code=1)
                self.assertFalse(any(c[1][:2] == ["pip", "install"] for c in calls))
                self.assertFalse((self.home / ".virtualenvs/nvim/.dotfiles-provider.json").exists())

    def test_existing_cache_inode_swap_refuses_later_command(self):
        cache = self.home / ".cache/uv"
        cache.mkdir(parents=True)
        self.env.update(FIXTURE_UV_SWAP=".cache/uv", SWAP_MODE="directory")
        _, calls = self.run_cli("--apply", "--feature", "provider", code=1)
        self.assertFalse(any(c[1][:2] == ["pip", "install"] for c in calls))

    def test_runtime_owned_dirs_and_bob_config_swaps_refuse_later_command(self):
        for index, relative in enumerate((".local/share/mise", ".cache/mise", ".local/share/bob", ".local/state/dotfiles-bob")):
            with self.subTest(path=relative):
                self.home = self.root / ("runtime swap home " + str(index))
                self.home.mkdir()
                self.env.update(HOME=str(self.home), RUNTIME_SWAP=relative)
                _, calls = self.run_cli("--apply", "--feature", "runtimes", code=1)
                self.assertFalse(any(c[0] == "bob" for c in calls))
        self.env.pop("RUNTIME_SWAP")
        self.home = self.root / "bob config swap home"
        self.home.mkdir()
        self.env.update(HOME=str(self.home), FIXTURE_BOB_CONFIG_SWAP="1")
        _, calls = self.run_cli("--apply", "--feature", "runtimes", code=1)
        self.assertFalse(any(c[1] == ["use", "0.11.7"] for c in calls))

    def test_mise_cannot_adopt_bob_directories_or_config(self):
        for index, path in enumerate((".local/share/bob", ".local/state/dotfiles-bob")):
            with self.subTest(path=path):
                self.home = self.root / ("mise bob swap home " + str(index))
                self.home.mkdir()
                self.env.update(HOME=str(self.home), RUNTIME_SWAP=path, SWAP_MODE="directory")
                _, calls = self.run_cli("--apply", "--feature", "runtimes", code=1)
                self.assertFalse(any(c[0] == "bob" for c in calls))
        self.env.pop("RUNTIME_SWAP")
        self.home = self.root / "mise bob config home"
        self.home.mkdir()
        self.env.update(HOME=str(self.home), FIXTURE_RUNTIME_CONFIG_CREATE="1")
        _, calls = self.run_cli("--apply", "--feature", "runtimes", code=1)
        self.assertFalse(any(c[0] == "bob" for c in calls))

    def test_runtime_nested_install_symlinks_refuse_all_preflight(self):
        for relative in (".local/share/mise/installs", ".local/share/mise/installs/node",
                         ".local/share/mise/installs/ruby", ".local/share/mise/installs/ruby/3.4.9",
                         ".local/share/mise/installs/node/24.16.0"):
            with self.subTest(path=relative):
                target = self.home / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                saved = target.with_name(target.name + ".saved")
                if target.exists():
                    target.rename(saved)
                target.symlink_to(self.root)
                _, calls = self.run_cli("--apply", "--feature", "shell", "--feature", "runtimes", code=1, readonly=True)
                self.assertEqual([], calls)
                target.unlink()
                if saved.exists():
                    saved.rename(target)

    def test_runtime_existing_install_version_inode_swap_refuses_bob(self):
        self.env.update(RUNTIME_SWAP=".local/share/mise/installs/node/24.16.0", SWAP_MODE="directory")
        _, calls = self.run_cli("--apply", "--feature", "runtimes", code=1)
        self.assertFalse(any(c[0] == "bob" for c in calls))

    def test_bob_uses_owned_explicit_config_without_reading_or_changing_user_config(self):
        user_config = self.home / ".config/bob/config.json"
        user_config.parent.mkdir(parents=True)
        user_config.write_text("PRIVATE_SECRET_DO_NOT_READ_OR_CHANGE")
        self.env["BOB_CONFIG"] = str(user_config)
        _, calls = self.run_cli("--apply", "--feature", "runtimes")
        config = self.home / ".local/state/dotfiles-bob/config.json"
        expected = {"downloads_location": str(self.home / ".local/share/bob"),
                    "installation_location": str(self.home / ".local/share/bob/nvim-bin"),
                    "add_neovim_binary_to_path": False}
        self.assertEqual(expected, json.loads(config.read_text()))
        for name, _, env in calls:
            if name == "bob":
                self.assertEqual(str(config), env["BOB_CONFIG"])
        self.assertEqual("PRIVATE_SECRET_DO_NOT_READ_OR_CHANGE", user_config.read_text())
        original = config.stat().st_ino
        self.run_cli("--apply", "--feature", "runtimes", readonly=True)
        self.assertEqual(original, config.stat().st_ino)

    def test_bob_writable_leaf_symlinks_refuse_all_preflight(self):
        for relative in (".local/share/bob/used", ".local/share/bob/nvim-bin/nvim"):
            with self.subTest(path=relative):
                path = self.home / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(self.home / ".env")
                _, calls = self.run_cli("--apply", "--feature", "shell", "--feature", "runtimes", code=1, readonly=True)
                self.assertEqual([], calls)
                path.unlink()

    def test_bob_writable_leaf_swaps_block_later_actions(self):
        for command, key in (("mise", "RUNTIME_SWAP"), ("bob", "FIXTURE_BOB_LEAF_SWAP")):
            for relative in (".local/share/bob/used", ".local/share/bob/nvim-bin/nvim"):
                with self.subTest(command=command, path=relative):
                    temp = tempfile.TemporaryDirectory(prefix="Bob leaf swap ", dir=self.root)
                    self.addCleanup(temp.cleanup)
                    self.home = Path(temp.name).resolve()
                    self.env.update(HOME=str(self.home))
                    self.env.pop("RUNTIME_SWAP", None)
                    self.env.pop("FIXTURE_BOB_LEAF_SWAP", None)
                    self.env[key] = relative
                    _, calls = self.run_cli("--apply", "--feature", "runtimes", code=1)
                    self.assertFalse(any(c[1] == ["use", "0.11.7"] for c in calls))
                    if command == "mise":
                        self.assertFalse(any(c[0] == "bob" for c in calls))

    def test_only_bob_use_can_create_selection_and_proxy_leaves(self):
        self.env["FIXTURE_BOB_CREATE_STAGE"] = "install"
        _, calls = self.run_cli("--apply", "--feature", "runtimes", code=1)
        self.assertFalse(any(c[1] == ["use", "0.11.7"] for c in calls))
        temp = tempfile.TemporaryDirectory(prefix="Bob use outputs ", dir=self.root)
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name).resolve()
        self.env.update(HOME=str(self.home), FIXTURE_BOB_CREATE_STAGE="use")
        self.run_cli("--apply", "--feature", "runtimes")
        self.assertTrue((self.home / ".local/share/bob/used").is_file())
        self.assertTrue((self.home / ".local/share/bob/nvim-bin/nvim").is_file())

    def test_mason_current_and_legacy_receipts_are_metadata_only(self):
        path = self.home / ".local/share/nvim/mason/packages/stylua/mason-receipt.json"
        path.parent.mkdir(parents=True)
        for schema, source, expected in (("1.1", "primary_source", "OK"), ("2.0", "source", "OK"), ("3.0", "source", "WARN")):
            with self.subTest(schema=schema):
                path.write_text(json.dumps({"name": "stylua", "schema_version": schema,
                                            "links": {"bin": {"stylua": "stylua"}},
                                            source: {"type": "registry+v1", "id": "pkg:github/johnnymorganz/stylua@v2.5.2"}}))
                output, calls = self.run_cli("--check", readonly=True)
                self.assertIn(expected + " [editor] Mason receipt stylua", output)
                self.assertEqual([], calls)
                self.assertIn("runtime health remains unverified", output)

    def test_bob_managed_config_symlink_refuses_all_preflight(self):
        config = self.home / ".local/state/dotfiles-bob/config.json"
        config.parent.mkdir(parents=True)
        config.symlink_to(self.home / ".env")
        _, calls = self.run_cli("--apply", "--feature", "shell", "--feature", "runtimes", code=1, readonly=True)
        self.assertEqual([], calls)

    def test_node_owned_paths_swapped_after_preflight_refuse_exec(self):
        for index, relative in enumerate(("Library/pnpm/global", "Library/Caches/dotfiles-corepack",
                                         ".local/share/mise/installs/node/24.16.0/bin")):
            with self.subTest(path=relative):
                self.home = self.root / ("node swap home " + str(index))
                self.home.mkdir()
                prefix = self.home / ".local/share/mise/installs/node/24.16.0"
                (prefix / "bin").mkdir(parents=True)
                for name in ("node", "corepack"):
                    (prefix / "bin" / name).write_text("not executed")
                    (prefix / "bin" / name).chmod(0o755)
                self.env.update(HOME=str(self.home), NODE_PREFIX=str(prefix), AFTER_CLONE_SWAP=relative)
                _, calls = self.run_cli("--apply", "--feature", "shell", "--feature", "node-tools", code=1)
                self.assertFalse(any(c[0] == "mise" for c in calls))

    def test_readonly_git_inspection_does_not_prepend_unrelated_pnpm_bin(self):
        self.existing_repo()
        malicious = self.home / "Library/pnpm/bin/git"
        malicious.parent.mkdir(parents=True)
        malicious.write_text("#!" + sys.executable + "\nimport pathlib, os\n"
                             "pathlib.Path(os.environ['HOME'], 'private-git-executed').touch()\n")
        malicious.chmod(0o755)
        _, calls = self.run_cli("--check", readonly=True)
        self.assertEqual(2, len(calls))

    def test_provider_refuses_python_redirect_outside_owned_provider_and_uv_install(self):
        target = self.home / "private runtime/python"
        target.parent.mkdir()
        target.write_text("not executed")
        target.chmod(0o755)
        self.env["FIXTURE_PYTHON_REDIRECT"] = str(target)
        _, calls = self.run_cli("--apply", "--feature", "provider", code=1)
        self.assertFalse(any(c[1][:2] == ["pip", "install"] for c in calls))

    def test_unrelated_action_cannot_adopt_new_owned_cache_directory(self):
        for index, (feature, path, command) in enumerate((("provider", ".cache/uv", "uv"),
                                                        ("runtimes", ".local/share/bob", "mise"),
                                                        ("node-tools", "Library/pnpm/global", "mise"))):
            with self.subTest(feature=feature):
                self.home = self.root / ("new directory home " + str(index))
                self.home.mkdir()
                prefix = self.home / ".local/share/mise/installs/node/24.16.0"
                (prefix / "bin").mkdir(parents=True)
                for name in ("node", "corepack"):
                    (prefix / "bin" / name).write_text("not executed")
                    (prefix / "bin" / name).chmod(0o755)
                self.env.update(HOME=str(self.home), NODE_PREFIX=str(prefix),
                                AFTER_CLONE_SWAP=path, SWAP_MODE="directory")
                _, calls = self.run_cli("--apply", "--feature", "shell", "--feature", feature, code=1)
                self.assertFalse(any(c[0] == command for c in calls))

    def test_uv_archive_cache_and_global_python_redirections_are_normalized(self):
        self.env.update(UV_PYTHON_CACHE_DIR=str(self.root / "private cache"),
                        UV_PYTHON_BIN_DIR=str(self.root / "global bin"), UV_PROJECT_ENVIRONMENT="private",
                        UV_PYTHON=str(self.root / "private interpreter"), UV_PYTHON_PREFERENCE="system")
        _, calls = self.run_cli("--apply", "--feature", "provider")
        for _, _, env in calls:
            self.assertEqual(str(self.home / ".cache/uv-python"), env["UV_PYTHON_CACHE_DIR"])
            self.assertEqual(str(self.home / ".local/share/uv/python"), env["UV_PYTHON_INSTALL_DIR"])
            self.assertEqual("only-managed", env["UV_PYTHON_PREFERENCE"])
            self.assertEqual("1", env["UV_NO_CONFIG"])
            for key in ("UV_PYTHON_BIN_DIR", "UV_PROJECT_ENVIRONMENT", "UV_PYTHON"):
                self.assertNotIn(key, env)

    def test_uv_archive_cache_symlink_refuses_all_preflight(self):
        cache = self.home / ".cache/uv-python"
        cache.parent.mkdir(parents=True)
        cache.symlink_to(self.root)
        _, calls = self.run_cli("--apply", "--feature", "shell", "--feature", "provider", code=1, readonly=True)
        self.assertEqual([], calls)

    def test_node_tools_accepts_shell_base_pnpm_home_without_mutation(self):
        self.env["PNPM_HOME"] = str(self.home / "Library/pnpm")
        _, calls = self.run_cli("--feature", "node-tools", readonly=True)
        self.assertEqual([], calls)
        _, calls = self.run_cli("--apply", "--feature", "node-tools", readonly=True)
        self.assertEqual(str(self.home / "Library/pnpm/bin"), calls[-1][2]["PNPM_HOME"])

    def test_node_tools_requires_owned_stable_node24_metadata(self):
        prefix = Path(self.env["NODE_PREFIX"])
        prefix.rename(prefix.with_name("24.16.0-rc.1"))
        _, calls = self.run_cli("--apply", "--feature", "node-tools", "--feature", "shell", code=1, readonly=True)
        self.assertEqual([], calls)

    def test_workspace_strict_age_missing_time_required(self):
        (self.repo / "dotfiles/pnpm-workspace.yaml").write_text("minimumReleaseAge: 10080\n")
        _, calls = self.run_cli("--apply", "--feature", "node-tools", "--feature", "shell", code=1, readonly=True)
        self.assertEqual([], calls)

    def test_editor_manifest_has_exact_public_repositories_and_parser_candidate_pin(self):
        repos = {r["name"]: r for r in self.manifest["repos"]}
        self.assertEqual({"oh-my-zsh", "tpm", "tmux-sensible", "tmux-resurrect", "tmux-fingers",
                          "nvim-jupyter", "tree-sitter-mustache"}, set(repos))
        parser = repos["tree-sitter-mustache"]
        self.assertEqual({"name": "tree-sitter-mustache", "feature": "editor",
                          "path": "peter-projects/tree-sitter-mustache",
                          "url": "https://github.com/TheLeoP/tree-sitter-mustache.git",
                          "sha": "0f1f3cf07508a64b84cbff457f1446a787c48a0e"}, parser)
        self.existing_repo("nvim-jupyter")
        self.existing_repo("tree-sitter-mustache")
        output, calls = self.run_cli("--apply", "--feature", "editor", readonly=True)
        self.assertIn("unverified", output.lower())
        self.assertFalse(any("status" in c[1] or "checkout" in c[1] or "clone" in c[1] for c in calls))

    def test_work_inventory_is_additive_and_excludes_competing_services(self):
        brewfile = (self.repo / "Brewfile.work").read_text()
        for formula in ("bison", "libyaml", "openssl@3", "mysql-client@8.0", "lame",
                        "openresty/brew/openresty", "libmaxminddb", "ffmpeg", "graphviz",
                        "imagemagick", "jemalloc", "protobuf"):
            self.assertIn('brew "' + formula + '"', brewfile)
        self.assertIn('tap "openresty/brew"', brewfile)
        for forbidden in ('brew "percona-toolkit"', 'brew "mailcatcher"', 'brew "yarn"',
                          'brew "corepack"', 'brew "mysql"', 'cask ', 'restart_service', 'link:'):
            self.assertNotIn(forbidden, brewfile)


if __name__ == "__main__":
    unittest.main()
