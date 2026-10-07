"""Phase-2 contracts; run with python3 -B -m unittest discover -s dotfiles/tests."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "scripts/bootstrap-mac"
NAMES = ("settings.json", "keybindings.json")
BREW_ENV = ("HOMEBREW_NO_AUTO_UPDATE", "HOMEBREW_NO_ANALYTICS", "HOMEBREW_NO_INSTALL_CLEANUP",
            "HOMEBREW_BUNDLE_FORCE_INSTALL_CLEANUP", "HOMEBREW_BUNDLE_INSTALL_CLEANUP")
STUB = '''import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
keys = ("HOMEBREW_NO_AUTO_UPDATE", "HOMEBREW_NO_ANALYTICS", "HOMEBREW_NO_INSTALL_CLEANUP",
        "HOMEBREW_BUNDLE_FORCE_INSTALL_CLEANUP", "HOMEBREW_BUNDLE_INSTALL_CLEANUP")
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps([name, args, {k: os.getenv(k) for k in keys}]) + "\\n")
if name == "uname" and args == ["-s"]:
    print(os.getenv("PLATFORM", "Darwin")); sys.exit(0)
if name == "xcode-select" and args == ["-p"]:
    print(os.environ["ROOT"] + "/CommandLineTools"); sys.exit(int(os.getenv("CLT_FAIL", "0")))
if name == "brew" and args == ["--prefix"]:
    print(os.environ["PREFIX"]); sys.exit(int(os.getenv("PREFIX_FAIL", "0")))
if name == "brew" and len(args) == 4 and args[:2] == ["bundle", "install"] and set(args[2:]) == {
        "--no-upgrade", "--file=" + os.environ["REPO"] + "/Brewfile"}:
    sys.exit(int(os.getenv("INSTALL_FAIL", "0")))
sys.exit(97)
'''


class BootstrapMacTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SOURCE.is_file(), "RED: missing implementation: " + str(SOURCE))
        temp = tempfile.TemporaryDirectory(prefix="bootstrap fixture ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.home, self.repo = self.root / "fake home", self.root / "separate repo"
        self.bin, self.cwd = self.root / "stub bin", self.root / "unrelated cwd"
        for path in (self.home, self.repo / "dotfiles/scripts", self.repo / ".vscode", self.bin, self.cwd):
            path.mkdir(parents=True)
        self.script = self.repo / "dotfiles/scripts/bootstrap-mac"
        shutil.copy2(SOURCE, self.script)
        (self.repo / "Brewfile").write_text('brew "git"\n')
        for name in NAMES:
            (self.repo / ".vscode" / name).write_text('{}\n' if name == NAMES[0] else '[]\n')
        self.target = self.home / "Library/Application Support/Code/User"
        self.backups = self.home / "Library/Application Support/dotfiles-backups"
        self.log = self.root / "commands.jsonl"
        self.env = {"HOME": str(self.home), "PATH": str(self.bin) + ":/usr/bin:/bin",
                    "ROOT": str(self.root), "REPO": str(self.repo), "LOG": str(self.log),
                    "LC_ALL": "C", "PYTHONDONTWRITEBYTECODE": "1",
                    "HOMEBREW_BUNDLE_FORCE_INSTALL_CLEANUP": "1",
                    "HOMEBREW_BUNDLE_INSTALL_CLEANUP": "1", "SENTINEL": str(self.root / "SOURCED")}
        compile(STUB, "fixture stub", "exec")
        for name in ("brew", "uname", "xcode-select", "curl", "mise", "bob", "nvim", "git",
                     "wget", "sudo", "launchctl", "chsh"):
            path = self.bin / name
            path.write_text("#!" + sys.executable + "\n" + STUB)
            path.chmod(0o755)
        for directory in (self.home, self.repo):
            for name in (".env", ".zshrc"):
                (directory / name).write_text('echo PRIVATE_SENTINEL; touch "$SENTINEL"\n')
        self.prefix("opt/homebrew")

    def prefix(self, layout):
        path = self.root / layout
        path.mkdir(parents=True, exist_ok=True)
        self.env["PREFIX"] = str(path)

    def snapshot(self, root=None):
        root = root or self.root
        return {str(p.relative_to(root)): (p.lstat().st_mode, p.lstat().st_ino,
                os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
                for p in root.rglob("*") if p != self.log}

    def run_bootstrap(self, *args, code=0, readonly=True, script=None):
        if self.log.exists():
            self.log.unlink()
        before = self.snapshot()
        result = subprocess.run(["/bin/bash", str(script or self.script), *args], cwd=self.cwd,
                                env=self.env, text=True, capture_output=True, timeout=10)
        output = result.stdout + result.stderr
        after = self.snapshot()
        if readonly:
            self.assertEqual(before, after, "Unexpected fixture mutation")
        else:
            allowed = {str(p.relative_to(self.root)) for p in (self.target, self.backups,
                       *self.target.parents, *self.backups.parents) if p != self.root and self.root in p.parents}
            for key in before.keys() | after.keys():
                path = self.root / key
                if key not in allowed and self.target not in path.parents and self.backups not in path.parents:
                    self.assertEqual(before.get(key), after.get(key), "Unexpected mutation: " + key)
        self.assertNotIn("PRIVATE_SENTINEL", output)
        self.assertFalse((self.root / "SOURCED").exists(), "Private shell files were sourced")
        self.assertEqual(code, result.returncode, output)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        for tool, argv, env in calls:
            if tool == "brew" and argv[:2] == ["bundle", "install"]:
                self.assertIn("--install", args)
                self.assertEqual(4, len(argv))
                self.assertEqual({"--no-upgrade", "--file=" + str(self.repo / "Brewfile")}, set(argv[2:]))
                self.assertEqual(["1", "1", "1", None, None], [env[k] for k in BREW_ENV])
            else:
                self.assertIn((tool, argv), [("uname", ["-s"]), ("brew", ["--prefix"]),
                                            ("xcode-select", ["-p"])], "Forbidden command")
        return output, calls

    def installs(self, calls):
        return [c for c in calls if c[0] == "brew" and c[1][:2] == ["bundle", "install"]]

    def assert_links(self):
        for name in NAMES:
            path, source = self.target / name, self.repo / ".vscode" / name
            self.assertTrue(path.is_symlink(), str(path))
            self.assertEqual(str(source), os.readlink(path))
            self.assertTrue(os.path.samefile(path, source))

    def test_help_and_invalid_flags_stop_before_checks(self):
        self.env["HOME"] = "relative home"
        for args, code in ((["--help"], 0), (["--unknown"], 2), (["--backup"], 2),
                           (["--install", "--backup"], 2), (["--dry-run", "--install"], 2),
                           (["--dry-run", "--link-vscode"], 2), (["--dry-run", "--backup"], 2),
                           (["--link-vscode", "--unknown"], 2), (["--help", "--unknown"], 2)):
            with self.subTest(args=args):
                output, calls = self.run_bootstrap(*args, code=code)
                self.assertEqual([], calls)
                self.assertTrue(output.strip())

    def test_default_and_dry_run_preview_both_actions_without_effects(self):
        for args in ((), ("--dry-run",)):
            output, calls = self.run_bootstrap(*args)
            for name in ("Brewfile", *NAMES):
                self.assertIn(name, output)
            self.assertRegex(output.lower(), r"preview|dry.run|would")
            self.assertEqual([], self.installs(calls))

    def test_preview_missing_tools_and_conflicts_remains_read_only(self):
        for name in ("brew", "xcode-select"):
            (self.bin / name).unlink()
        self.target.mkdir(parents=True)
        (self.target / NAMES[0]).write_text("existing preferences")
        output, calls = self.run_bootstrap("--dry-run")
        self.assertRegex(output.lower(), r"warn|missing|unavailable|conflict|not found")
        self.assertEqual([], self.installs(calls))

    def test_unsupported_platform_refuses_every_normal_mode(self):
        self.env["PLATFORM"] = "Linux"
        for args in ((), ("--dry-run",), ("--install",), ("--link-vscode",)):
            output, calls = self.run_bootstrap(*args, code=1)
            self.assertRegex(output.lower(), r"darwin|macos|platform|linux")
            self.assertEqual([], self.installs(calls))

    def test_home_must_be_an_existing_absolute_directory(self):
        for home in ("", "relative", str(self.root / "missing"), str(self.repo / "Brewfile")):
            self.env["HOME"] = home
            for args in ((), ("--install",), ("--link-vscode",)):
                _, calls = self.run_bootstrap(*args, code=1)
                self.assertEqual([], self.installs(calls))

    def test_missing_brew_or_clt_refuses_install(self):
        dirname = shutil.which("dirname")
        if dirname is None:
            raise RuntimeError("Test fixtures require dirname")
        (self.bin / "dirname").symlink_to(dirname)
        for tool in ("brew", "xcode-select"):
            path = self.bin / tool
            content = path.read_bytes()
            path.unlink()
            original_path = self.env["PATH"]
            self.env["PATH"] = str(self.bin) + ":/bin"
            _, calls = self.run_bootstrap("--install", code=1)
            self.assertEqual([], self.installs(calls))
            self.env["PATH"] = original_path
            path.write_bytes(content)
            path.chmod(0o755)
        self.env["CLT_FAIL"] = "1"
        _, calls = self.run_bootstrap("--install", code=1)
        self.assertEqual([], self.installs(calls))

    def test_invalid_prefix_refuses_install_before_effects(self):
        for changes in ({"PREFIX_FAIL": "1"}, {"PREFIX": ""}, {"PREFIX": str(self.root / "absent")},
                        {"PREFIX": str(self.repo / "Brewfile")}):
            old = self.env.copy()
            self.env.update(changes)
            _, calls = self.run_bootstrap("--install", code=1)
            self.assertEqual([], self.installs(calls))
            self.env = old

    def test_install_uses_physical_repo_and_both_prefixes_without_editor_inputs(self):
        shutil.rmtree(self.repo / ".vscode")
        alias = self.root / "repo alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        for layout in ("opt/homebrew", "usr/local"):
            self.prefix(layout)
            _, calls = self.run_bootstrap("--install", script=alias / "dotfiles/scripts/bootstrap-mac")
            self.assertEqual(1, len(self.installs(calls)))
        (self.repo / ".vscode").mkdir()
        for name in NAMES:
            (self.repo / ".vscode" / name).write_text("{}\n")
        _, calls = self.run_bootstrap("--install", "--link-vscode", readonly=False)
        self.assertEqual(1, len(self.installs(calls)))
        self.assert_links()

    def test_link_only_creates_two_links_without_brew_clt_or_brewfile_and_is_idempotent(self):
        for name in ("brew", "xcode-select"):
            (self.bin / name).unlink()
        (self.repo / "Brewfile").unlink()
        _, calls = self.run_bootstrap("--link-vscode", readonly=False)
        self.assert_links()
        self.assertFalse(self.backups.exists())
        self.assertFalse(any(c[0] in ("brew", "xcode-select") for c in calls))
        self.run_bootstrap("--link-vscode", "--backup")

    def test_correct_existing_links_and_same_inode_files_are_noops(self):
        self.target.mkdir(parents=True)
        (self.target / NAMES[0]).symlink_to(self.repo / ".vscode" / NAMES[0])
        os.link(self.repo / ".vscode" / NAMES[1], self.target / NAMES[1])
        self.run_bootstrap("--link-vscode", "--backup")
        self.assertFalse(self.backups.exists())

    def test_conflicting_files_wrong_and_dangling_links_refuse_without_backup(self):
        self.target.mkdir(parents=True)
        other = self.root / "other.json"
        other.write_text("wrong target")
        path = self.target / NAMES[1]
        for kind in ("file", "wrong", "dangling"):
            if kind == "file":
                path.write_text("keep me")
            else:
                path.symlink_to(other if kind == "wrong" else "missing relative.json")
            self.run_bootstrap("--link-vscode", code=1)
            path.unlink()

    def test_backup_preserves_modes_content_link_strings_and_prior_backups(self):
        self.target.mkdir(parents=True)
        other = self.root / "other.json"
        other.write_text("wrong target")
        for link in (str(other), "missing relative.json"):
            prior = self.snapshot(self.backups) if self.backups.exists() else {}
            old_dirs = set(self.backups.iterdir()) if self.backups.exists() else set()
            settings, keys = (self.target / name for name in NAMES)
            settings.write_bytes(b"private original\n")
            settings.chmod(0o640)
            keys.symlink_to(link)
            output, _ = self.run_bootstrap("--link-vscode", "--backup", readonly=False)
            self.assert_links()
            created = set(self.backups.iterdir()) - old_dirs
            self.assertEqual(1, len(created))
            backup = created.pop()
            self.assertTrue(backup.name.startswith("vscode."))
            self.assertEqual(0o700, backup.stat().st_mode & 0o777)
            self.assertEqual(set(NAMES), {p.name for p in backup.iterdir()})
            self.assertEqual(b"private original\n", (backup / NAMES[0]).read_bytes())
            self.assertEqual(0o640, (backup / NAMES[0]).stat().st_mode & 0o777)
            self.assertEqual(link, os.readlink(backup / NAMES[1]))
            self.assertRegex(output.lower(), r"backup|preserv")
            self.assertEqual(prior, {k: v for k, v in self.snapshot(self.backups).items() if k in prior})
            self.run_bootstrap("--link-vscode", "--backup")
            for path in (settings, keys):
                path.unlink()

    def test_directories_directory_links_and_fifos_refuse_even_with_backup(self):
        self.target.mkdir(parents=True)
        external = self.root / "external directory"
        external.mkdir()
        path = self.target / NAMES[1]
        for kind in ("directory", "directory link", "fifo"):
            with self.subTest(kind=kind):
                if kind == "directory":
                    path.mkdir()
                elif kind == "directory link":
                    path.symlink_to(external, target_is_directory=True)
                else:
                    os.mkfifo(path)
                _, calls = self.run_bootstrap("--install", "--link-vscode", "--backup", code=1)
                self.assertEqual([], self.installs(calls))
                path.rmdir() if kind == "directory" else path.unlink()

    def test_symlinked_target_or_backup_ancestors_refuse_before_effects(self):
        external = self.root / "external"
        external.mkdir()
        for relative in ("Library", "Library/Application Support", "Library/Application Support/Code",
                         "Library/Application Support/Code/User", "Library/Application Support/dotfiles-backups"):
            path = self.home / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(external, target_is_directory=True)
            _, calls = self.run_bootstrap("--install", "--link-vscode", "--backup", code=1)
            self.assertEqual([], self.installs(calls))
            path.unlink()

    def test_missing_selected_inputs_preflight_prevents_install_and_link_effects(self):
        for path in (self.repo / "Brewfile", *(self.repo / ".vscode" / n for n in NAMES)):
            data = path.read_bytes()
            path.unlink()
            for directory in (False, True):
                if directory:
                    path.mkdir()
                _, calls = self.run_bootstrap("--install", "--link-vscode", "--backup", code=1)
                self.assertEqual([], self.installs(calls))
                if directory:
                    path.rmdir()
            path.write_bytes(data)

    def test_failed_install_reports_failure_and_does_not_link_or_backup(self):
        for status in (1, 42):
            with self.subTest(status=status):
                self.env["INSTALL_FAIL"] = str(status)
                output, calls = self.run_bootstrap("--install", "--link-vscode", "--backup", code=status)
                self.assertEqual(1, len(self.installs(calls)))
                self.assertRegex(output.lower(), r"fail|error")


if __name__ == "__main__":
    unittest.main()
