"""Contract tests: python3 -B -m unittest discover -s dotfiles/tests -v."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "scripts/dotfiles-doctor"
REQUIRED = ("Brewfile", ".config/mise/config.toml",
            "dotfiles/scripts/dotfiles-doctor", "dotfiles/README.md")
OPTIONAL = ("Brewfile.work", "dotfiles/provisioning.json", "dotfiles/pnpm-workspace.yaml",
            "dotfiles/scripts/provision-optional")
TOOLS = ["brew", "git", "mise", "bob", "nvim", "uv", "node", "ruby", "tmux", "fzf",
         "rg", "fd", "gh", "lazygit", "delta", "git-lfs"]
NATIVE = ("powerlevel10k/powerlevel10k.zsh-theme",
          "zsh-autosuggestions/zsh-autosuggestions.zsh",
          "zsh-syntax-highlighting/zsh-syntax-highlighting.zsh")
STUB = '''import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps([name, args, os.getenv("HOMEBREW_NO_AUTO_UPDATE")]) + "\\n")
if name == "uname" and args == ["-s"]:
    print(os.getenv("PLATFORM", "Darwin")); sys.exit(0)
if name == "xcode-select" and args == ["-p"]:
    print("/fixture/CommandLineTools"); sys.exit(int(os.getenv("CLT_FAIL", "0")))
if name == "brew" and args == ["--prefix"]:
    print(os.environ["PREFIX"]); sys.exit(int(os.getenv("PREFIX_FAIL", "0")))
if name == "brew" and args[:2] == ["bundle", "check"] and len(args) == 5 and set(args[2:]) == {
        "--no-upgrade", "--verbose", "--file=" + os.environ["REPO"] + "/Brewfile"}:
    sys.exit(int(os.getenv("BUNDLE_FAIL", "0")))
if name == "git" and len(args) == 6 and args[:5] == [
        "-C", os.environ["REPO"], "ls-files", "--error-unmatch", "--"]:
    sys.exit(int(os.getenv("UNTRACKED") == args[5] or not
                 (pathlib.Path(os.environ["REPO"]) / args[5]).is_file()))
if name == "git" and args[:1] == ["-C"] and args[1] == os.environ["HOME"] + "/.oh-my-zsh":
    if args[2:] == ["rev-parse", "--show-toplevel"]: print(args[1]); sys.exit(0)
    if args[2:] == ["rev-parse", "HEAD"]: print("0" * 40); sys.exit(0)
    if args[2:] == ["status", "--porcelain", "--untracked-files=all"]: print("?? required.py"); sys.exit(0)
sys.exit(97)
'''


class DotfilesDoctorTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SOURCE.is_file(), "RED: dotfiles-doctor implementation does not exist")
        temp = tempfile.TemporaryDirectory(prefix="doctor fixture ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.home, self.repo = self.root / "fake home", self.root / "copied repo"
        self.bin, self.cwd = self.root / "stub bin", self.root / "unrelated cwd"
        for directory in (self.home, self.repo, self.bin, self.cwd):
            directory.mkdir()
        for name in REQUIRED:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if name == "dotfiles/scripts/dotfiles-doctor":
                shutil.copy2(SOURCE, path)
            else:
                path.write_text("# disposable fixture\n")
        self.script = self.repo / REQUIRED[2]
        self.log = self.root / "invocations.jsonl"
        self.env = {"PATH": str(self.bin) + ":/usr/bin:/bin", "HOME": str(self.home),
                    "REPO": str(self.repo), "LOG": str(self.log), "LC_ALL": "C",
                    "PYTHONDONTWRITEBYTECODE": "1",
                    "SENTINEL": str(self.home / "SOURCED")}
        for name in TOOLS + ["uname", "xcode-select", "curl", "wget", "zsh", "fish",
                             "pip", "pip3", "black", "isort", "prettier", "shfmt"]:
            path = self.bin / name
            path.write_text("#!" + sys.executable + "\n" + STUB)
            path.chmod(0o755)
        for name in (".zshenv", ".zprofile", ".zshrc", ".zlogin", ".bashrc", ".profile", ".env"):
            (self.home / name).write_text('echo PRIVATE_SENTINEL; echo sourced >> "$SENTINEL"\n')
        (self.repo / ".env").write_text('echo PRIVATE_SENTINEL; echo sourced >> "$SENTINEL"\n')
        self.prefix("opt/homebrew")
        self.query = self.repo / ".config/nvim/queries/mustache/highlights.scm"
        self.query.parent.mkdir(parents=True)
        target = self.home / "valid query.scm"
        target.write_text("; fixture\n")
        self.query.symlink_to(target)

    def prefix(self, suffix):
        path = self.root / suffix
        path.mkdir(parents=True, exist_ok=True)
        self.env["PREFIX"] = str(path)
        for name in NATIVE:
            file = path / "share" / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("# fixture\n")

    def snapshot(self):
        return {str(p.relative_to(self.root)): (p.lstat().st_mode,
                os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
                for p in self.root.rglob("*") if p != self.log}

    def run_doctor(self, *args, code=0):
        if self.log.exists():
            self.log.unlink()
        before = self.snapshot()
        result = subprocess.run(["/bin/bash", str(self.script), *args], cwd=self.cwd,
                                env=self.env, text=True, capture_output=True, timeout=10)
        output = result.stdout + result.stderr
        self.assertEqual(before, self.snapshot(), "Doctor must not mutate home/repo")
        self.assertNotIn("PRIVATE_SENTINEL", output)
        self.assertEqual(code, result.returncode, output)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        allowed = [("uname", ["-s"]), ("xcode-select", ["-p"]), ("brew", ["--prefix"])]
        allowed += [("git", ["-C", str(self.repo), "ls-files", "--error-unmatch", "--", name])
                    for name in REQUIRED + OPTIONAL]
        allowed += [("git", ["-C", str(self.home / ".oh-my-zsh"), *argv]) for argv in (
                    ["rev-parse", "--show-toplevel"], ["rev-parse", "HEAD"],
                    ["status", "--porcelain", "--untracked-files=all"])]
        for tool, argv, auto_update in calls:
            if tool == "brew" and argv[:2] == ["bundle", "check"]:
                self.assertIn("--brew-check", args)
                self.assertEqual(5, len(argv))
                self.assertEqual({"--no-upgrade", "--verbose", "--file=" + str(self.repo / "Brewfile")}, set(argv[2:]))
                self.assertEqual("1", auto_update)
            else:
                self.assertIn((tool, argv), allowed, "Forbidden execution: " + str((tool, argv)))
        return output, calls

    def status(self, output, severity, category, fragment):
        self.assertRegex(output, r"(?im)^" + severity + r" \[" + category + r"\].*"
                         + re.escape(fragment) + r"(?:\b|$)")

    def test_help_and_unknown_arguments_do_not_run_checks(self):
        for args, code in ((["--help"], 0), (["--unknown"], 2), (["--brew-check", "--unknown"], 2)):
            with self.subTest(args=args):
                output, calls = self.run_doctor(*args, code=code)
                self.assertEqual([], calls)
                self.assertTrue(output.strip())
                if code == 0:
                    self.assertIn("--brew-check", output)

    def test_ready_base_is_read_only_and_conclusion_does_not_claim_editor_readiness(self):
        output, calls = self.run_doctor()
        for tool in TOOLS:
            self.status(output, "OK", "base", tool)
        self.assertNotRegex(output, r"(?m)^(?:ERROR|MISSING) \[base\]")
        self.assertNotRegex(output, r"(?im)^.*\[base\].*\b(?:black|isort|prettier|prettierd|shfmt)\b")
        conclusion = "\n".join(line for line in output.splitlines()
                               if not re.match(r"^(OK|WARN|MISSING|ERROR) \[", line))
        self.assertRegex(conclusion.lower(), r"(?:only|limited|not|unchecked|unverified|unassessed|cannot)")
        self.assertRegex(conclusion.lower(), r"(?:base|editor|neovim|nvim|readiness)")
        self.assertNotRegex(output.lower(), r"all dotfiles (?:are )?portable")
        for tool, argv in [("uname", ["-s"]), ("xcode-select", ["-p"]), ("brew", ["--prefix"])]:
            self.assertIn((tool, argv), [(c[0], c[1]) for c in calls])
        tracked = {c[1][-1] for c in calls if c[0] == "git"}
        self.assertEqual(set(REQUIRED), tracked)

    def test_missing_rg_fails_base_without_running_other_available_tools(self):
        (self.bin / "rg").unlink()
        output, _ = self.run_doctor(code=1)
        self.status(output, "MISSING", "base", "rg")

    def test_bad_brew_prefix_status_empty_or_non_directory_fails_base(self):
        for changes in ({"PREFIX_FAIL": "1"}, {"PREFIX": ""}, {"PREFIX": str(self.root / "absent")},
                        {"PREFIX": str(self.repo / "Brewfile")}):
            with self.subTest(changes=changes):
                original = self.env.copy()
                self.env.update(changes)
                output, _ = self.run_doctor(code=1)
                self.status(output, "(?:ERROR|MISSING)", "base", "brew")
                self.env = original

    def test_missing_clt_and_unsupported_platform_fail_base(self):
        for changes, subject in (({"CLT_FAIL": "1"}, r"(?:xcode|command.line|CLT|developer)"),
                                 ({"PLATFORM": "Linux"}, r"(?:Darwin|macOS|platform|Linux)")):
            with self.subTest(changes=changes):
                self.env.update(changes)
                output, _ = self.run_doctor(code=1)
                self.assertRegex(output, r"(?im)^(?:ERROR|MISSING) \[base\].*" + subject)
                for key in changes:
                    self.env.pop(key)

    def test_missing_or_untracked_required_inputs_fail_base(self):
        for name in REQUIRED:
            with self.subTest(name=name):
                self.env["UNTRACKED"] = name
                output, _ = self.run_doctor(code=1)
                self.status(output, "(?:ERROR|MISSING)", "base", name)
        self.env.pop("UNTRACKED")
        for name in (REQUIRED[0], REQUIRED[1], REQUIRED[3]):
            path = self.repo / name
            content = path.read_bytes()
            path.unlink()
            output, _ = self.run_doctor(code=1)
            self.status(output, "(?:ERROR|MISSING)", "base", name)
            path.write_bytes(content)

    def test_both_homebrew_layouts_with_spaces_and_missing_native_dependencies(self):
        for layout in ("opt/homebrew", "usr/local"):
            self.prefix(layout)
            self.run_doctor()
            for name in NATIVE:
                path = Path(self.env["PREFIX"]) / "share" / name
                path.unlink()
                output, _ = self.run_doctor(code=1)
                self.status(output, "(?:ERROR|MISSING)", "base", Path(name).name)
                path.write_text("# fixture\n")

    def test_missing_local_features_and_broken_absolute_queries_are_warnings(self):
        self.query.unlink()
        self.query.symlink_to(self.home / "absent checkout/query.scm")
        output, _ = self.run_doctor()
        for subject in ("python3", "nvim-jupyter", "highlights.scm"):
            self.status(output, "WARN", "editor", subject)
        for subject in ("oh-my-zsh", "tpm"):
            self.status(output, "WARN", "optional", subject)

    def test_optional_inputs_untracked_checkouts_dirty_and_mason_metadata_are_warnings(self):
        for name in OPTIONAL:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE.parents[2] / name, path)
        self.env["UNTRACKED"] = "dotfiles/provisioning.json"
        checkout = self.home / ".oh-my-zsh"
        (checkout / ".git").mkdir(parents=True)
        receipt = self.home / ".local/share/nvim/mason/packages/black/mason-receipt.json"
        receipt.parent.mkdir(parents=True)
        receipt.write_text(json.dumps({"name": "black", "schema_version": "2.0", "links": {"bin": {}},
                                       "source": {"type": "registry+v1", "id": "pkg:pypi/black@24.1.0"}}))
        output, calls = self.run_doctor()
        self.status(output, "WARN", "optional", "dotfiles/provisioning.json")
        self.status(output, "WARN", "optional", "Dirty")
        self.status(output, "WARN", "optional", "revision")
        self.status(output, "OK", "editor", "black")
        self.status(output, "WARN", "editor", "debugpy")
        self.assertIn("metadata", output.lower())
        self.assertNotRegex(output, r"(?m)^(?:ERROR|MISSING) \\[base\\]")
        self.assertFalse(any(c[0] == "git" and "status" in c[1] for c in calls))

    def test_opt_in_brew_check_is_non_upgrading_and_failure_is_base_error(self):
        for fail in ("0", "1"):
            self.env["BUNDLE_FAIL"] = fail
            output, calls = self.run_doctor("--brew-check", code=int(fail))
            self.assertTrue(any(c[0] == "brew" and c[1][:2] == ["bundle", "check"] for c in calls))
            if fail == "1":
                self.status(output, "ERROR", "base", "brew")


if __name__ == "__main__":
    unittest.main()
