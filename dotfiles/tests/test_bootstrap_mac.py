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
        self.skills_source = self.home / "peter-projects/pi-config/skills"
        self.skills_target = self.home / ".agents/skills"
        self.instructions_source = self.home / "peter-projects/pi-config/AGENTS.md"
        self.instructions_target = self.home / ".codex/AGENTS.md"
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
            managed = (self.target, self.backups, self.skills_target, self.instructions_target)
            allowed = {str(p.relative_to(self.root)) for target in managed for p in (target, *target.parents)
                       if p != self.root and self.root in p.parents}
            for key in before.keys() | after.keys():
                path = self.root / key
                if key not in allowed and not any(target in path.parents for target in managed):
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

    def create_shared_skill(self):
        skill = self.skills_source / "example/SKILL.md"
        skill.parent.mkdir(parents=True)
        skill.write_text("---\nname: example\ndescription: Example skill\n---\n")

    def test_agent_skills_link_is_home_relative_and_idempotent_without_installers(self):
        self.create_shared_skill()
        for name in ("brew", "xcode-select"):
            (self.bin / name).unlink()
        (self.repo / "Brewfile").unlink()
        _, calls = self.run_bootstrap("--link-agent-skills", readonly=False)
        self.assertTrue(self.skills_target.is_symlink())
        self.assertEqual(str(self.skills_source), os.readlink(self.skills_target))
        self.assertEqual((self.skills_source / "example/SKILL.md").read_text(),
                         (self.skills_target / "example/SKILL.md").read_text())
        self.assertFalse(self.target.exists())
        self.assertFalse(any(c[0] in ("brew", "xcode-select") for c in calls))
        self.run_bootstrap("--link-agent-skills")
        self.assertEqual(["example"], sorted(p.name for p in self.skills_source.iterdir()))

    def test_agent_skills_preview_reports_link_and_missing_source_without_writes(self):
        output, _ = self.run_bootstrap("--dry-run")
        self.assertIn(str(self.skills_source), output)
        self.assertIn(str(self.skills_target), output)
        self.assertRegex(output.lower(), r"warn|missing")
        self.create_shared_skill()
        output, _ = self.run_bootstrap("--dry-run")
        self.assertIn(str(self.skills_target), output)
        self.assertIn(str(self.skills_source), output)
        self.assertFalse(self.skills_target.parent.exists())

    def test_agent_skills_missing_source_preflights_all_selected_actions(self):
        for kind in ("missing", "file"):
            with self.subTest(kind=kind):
                if kind == "file":
                    self.skills_source.parent.mkdir(parents=True)
                    self.skills_source.write_text("not a directory")
                _, calls = self.run_bootstrap("--install", "--link-vscode", "--link-agent-skills", code=1)
                self.assertEqual([], self.installs(calls))
                self.assertFalse(self.target.exists())
                self.assertFalse(self.skills_target.parent.exists())

    def test_agent_skills_combines_with_existing_actions_and_preserves_other_agent_files(self):
        self.create_shared_skill()
        local = self.skills_target.parent / "local/SKILL.md"
        local.parent.mkdir(parents=True)
        local.write_text("keep")
        _, calls = self.run_bootstrap("--install", "--link-vscode", "--link-agent-skills", readonly=False)
        self.assertEqual(1, len(self.installs(calls)))
        self.assert_links()
        self.assertTrue(self.skills_target.is_symlink())
        self.assertTrue(os.path.samefile(self.skills_target, self.skills_source))
        self.assertEqual("keep", local.read_text())

    def test_agent_skills_conflicts_are_preserved_even_with_vscode_backup(self):
        self.create_shared_skill()
        self.skills_target.parent.mkdir()
        foreign = self.root / "foreign skills"
        foreign.mkdir()
        for kind in ("empty directory", "nonempty directory", "file", "foreign link", "dangling link"):
            with self.subTest(kind=kind):
                if "directory" in kind:
                    self.skills_target.mkdir()
                    if kind == "nonempty directory":
                        (self.skills_target / "local.md").write_text("keep")
                elif kind == "file":
                    self.skills_target.write_text("keep")
                else:
                    self.skills_target.symlink_to(foreign if kind == "foreign link" else "missing")
                try:
                    _, calls = self.run_bootstrap("--install", "--link-vscode", "--backup",
                                                  "--link-agent-skills", code=1)
                    self.assertEqual([], self.installs(calls))
                    output, _ = self.run_bootstrap("--dry-run")
                    self.assertRegex(output.lower(), r"warn|conflict")
                finally:
                    if self.skills_target.is_dir() and not self.skills_target.is_symlink():
                        shutil.rmtree(self.skills_target)
                    else:
                        self.skills_target.unlink()

    def test_agent_skills_parent_symlink_or_file_refuses_without_effects(self):
        self.create_shared_skill()
        foreign = self.root / "foreign parent"
        foreign.mkdir()
        parent = self.skills_target.parent
        for kind in ("symlink", "file"):
            with self.subTest(kind=kind):
                if kind == "symlink":
                    parent.symlink_to(foreign, target_is_directory=True)
                else:
                    parent.write_text("keep")
                try:
                    _, calls = self.run_bootstrap("--install", "--link-agent-skills", code=1)
                    self.assertEqual([], self.installs(calls))
                finally:
                    parent.unlink()

    def test_agent_skills_correct_relative_directory_link_is_noop(self):
        self.create_shared_skill()
        self.skills_target.parent.mkdir()
        self.skills_target.symlink_to(os.path.relpath(self.skills_source, self.skills_target.parent),
                                      target_is_directory=True)
        self.run_bootstrap("--link-agent-skills")

    def test_agent_skills_invalid_flags_stop_before_checks(self):
        for args in (("--dry-run", "--link-agent-skills"), ("--link-agent-skills", "--backup")):
            _, calls = self.run_bootstrap(*args, code=2)
            self.assertEqual([], calls)

    def create_shared_instructions(self):
        self.instructions_source.parent.mkdir(parents=True, exist_ok=True)
        self.instructions_source.write_text("# Shared instructions\nUse pnpm.\n")

    def test_codex_instructions_link_is_idempotent_and_preserves_config(self):
        self.create_shared_instructions()
        config = self.instructions_target.parent / "config.toml"
        config.parent.mkdir()
        config.write_text('model = "local-model"\n')
        for name in ("brew", "xcode-select"):
            (self.bin / name).unlink()
        (self.repo / "Brewfile").unlink()
        _, calls = self.run_bootstrap("--link-codex-instructions", readonly=False)
        self.assertTrue(self.instructions_target.is_symlink())
        self.assertEqual(str(self.instructions_source), os.readlink(self.instructions_target))
        self.assertEqual(self.instructions_source.read_text(), self.instructions_target.read_text())
        self.assertEqual('model = "local-model"\n', config.read_text())
        self.assertFalse(any(c[0] in ("brew", "xcode-select") for c in calls))
        self.run_bootstrap("--link-codex-instructions")

    def test_codex_preview_reports_target_and_missing_source_read_only(self):
        output, _ = self.run_bootstrap("--dry-run")
        self.assertIn(str(self.instructions_source), output)
        self.assertIn(str(self.instructions_target), output)
        self.create_shared_instructions()
        output, _ = self.run_bootstrap("--dry-run")
        self.assertIn(str(self.instructions_target), output)
        self.assertFalse(self.instructions_target.parent.exists())

    def test_codex_missing_or_empty_source_preflights_all_selected_actions(self):
        self.create_shared_skill()
        for kind in ("missing", "empty", "directory"):
            with self.subTest(kind=kind):
                if kind == "empty":
                    self.instructions_source.write_text("")
                elif kind == "directory":
                    self.instructions_source.unlink()
                    self.instructions_source.mkdir()
                _, calls = self.run_bootstrap("--install", "--link-vscode", "--link-agent-skills",
                                              "--link-codex-instructions", code=1)
                self.assertEqual([], self.installs(calls))
                self.assertFalse(self.target.exists())
                self.assertFalse(self.skills_target.exists())

    def test_codex_conflicts_are_preserved_even_with_vscode_backup(self):
        self.create_shared_instructions()
        self.instructions_target.parent.mkdir()
        foreign = self.root / "foreign instructions.md"
        foreign.write_text("keep")
        for kind in ("file", "directory", "foreign link", "dangling link"):
            with self.subTest(kind=kind):
                if kind == "file":
                    self.instructions_target.write_text("keep")
                elif kind == "directory":
                    self.instructions_target.mkdir()
                else:
                    self.instructions_target.symlink_to(foreign if kind == "foreign link" else "missing")
                try:
                    _, calls = self.run_bootstrap("--install", "--link-vscode", "--backup",
                                                  "--link-codex-instructions", code=1)
                    self.assertEqual([], self.installs(calls))
                finally:
                    if kind == "directory":
                        self.instructions_target.rmdir()
                    else:
                        self.instructions_target.unlink()

    def test_codex_parent_symlink_or_file_refuses_without_effects(self):
        self.create_shared_instructions()
        foreign = self.root / "foreign codex"
        foreign.mkdir()
        parent = self.instructions_target.parent
        for kind in ("symlink", "file"):
            with self.subTest(kind=kind):
                if kind == "symlink":
                    parent.symlink_to(foreign, target_is_directory=True)
                else:
                    parent.write_text("keep")
                try:
                    _, calls = self.run_bootstrap("--install", "--link-codex-instructions", code=1)
                    self.assertEqual([], self.installs(calls))
                finally:
                    parent.unlink()

    def test_codex_override_precedence_is_detected_without_modifying_it(self):
        self.create_shared_instructions()
        override = self.instructions_target.parent / "AGENTS.override.md"
        override.parent.mkdir()
        override.write_text("Local override")
        output, calls = self.run_bootstrap("--install", "--link-codex-instructions", code=1)
        self.assertIn("AGENTS.override.md", output)
        self.assertEqual([], self.installs(calls))
        output, _ = self.run_bootstrap("--dry-run")
        self.assertIn("AGENTS.override.md", output)
        override.write_text("")
        self.run_bootstrap("--link-codex-instructions", readonly=False)
        self.assertTrue(self.instructions_target.is_symlink())

    def test_codex_correct_relative_link_is_noop(self):
        self.create_shared_instructions()
        self.instructions_target.parent.mkdir()
        self.instructions_target.symlink_to(
            os.path.relpath(self.instructions_source, self.instructions_target.parent))
        self.run_bootstrap("--link-codex-instructions")

    def test_codex_invalid_flags_stop_before_checks(self):
        for args in (("--dry-run", "--link-codex-instructions"), ("--link-codex-instructions", "--backup")):
            _, calls = self.run_bootstrap(*args, code=2)
            self.assertEqual([], calls)

    def test_codex_home_override_cannot_silently_link_inactive_default_profile(self):
        self.create_shared_instructions()
        for value in ("", str(self.instructions_target.parent)):
            self.env["CODEX_HOME"] = value
            self.run_bootstrap("--link-codex-instructions", readonly=False)
            self.assertTrue(os.path.samefile(self.instructions_target, self.instructions_source))
        self.instructions_target.unlink()
        for value in (str(self.home / "custom codex"), "relative codex"):
            with self.subTest(value=value):
                self.env["CODEX_HOME"] = value
                output, calls = self.run_bootstrap("--install", "--link-codex-instructions", code=1)
                self.assertIn("CODEX_HOME", output)
                self.assertEqual([], self.installs(calls))
                output, _ = self.run_bootstrap("--dry-run")
                self.assertIn("CODEX_HOME", output)
                self.assertFalse(self.instructions_target.exists())

    def test_codex_and_skills_can_be_linked_together(self):
        self.create_shared_skill()
        self.create_shared_instructions()
        self.run_bootstrap("--link-agent-skills", "--link-codex-instructions", readonly=False)
        self.assertTrue(os.path.samefile(self.skills_target, self.skills_source))
        self.assertTrue(os.path.samefile(self.instructions_target, self.instructions_source))

    def test_failed_install_reports_failure_and_does_not_link_or_backup(self):
        for status in (1, 42):
            with self.subTest(status=status):
                self.env["INSTALL_FAIL"] = str(status)
                output, calls = self.run_bootstrap("--install", "--link-vscode", "--backup", code=status)
                self.assertEqual(1, len(self.installs(calls)))
                self.assertRegex(output.lower(), r"fail|error")


if __name__ == "__main__":
    unittest.main()
