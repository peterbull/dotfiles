"""Isolated contracts: python3 -B -m unittest discover -s dotfiles/tests -p test_session_portability.py -v."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
BASH = next((p for p in ("/opt/homebrew/bin/bash", "/usr/local/bin/bash", shutil.which("bash"))
             if p and Path(p).is_file() and int(subprocess.check_output(
                 [p, "-c", "printf '%s' \"${BASH_VERSINFO[0]}\""]).decode()) >= 4), "")
STUB = r'''import json, os, pathlib, re, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps([name, args]) + "\n")
if name == "tmux":
    file = pathlib.Path(os.environ["STATE"])
    state = json.loads(file.read_text())
    command = args[0]
    if os.getenv("FAIL_TMUX") == command:
        print("fixture failure: " + command, file=sys.stderr); sys.exit(23)
    def option(flag, default=None):
        return args[args.index(flag)+1] if flag in args else default
    def target():
        value = option("-t") or option("-s")
        assert value.startswith("="), value
        return value[1:].split(":", 1)[0]
    def cwd():
        return re.sub(r"##|#\{[^}]*\}|#\([^)]*\)", lambda m: "#" if m[0] == "##" else "EXPANDED", option("-c"))
    sessions = state["sessions"]
    if command == "has-session":
        sys.exit(0 if target() in sessions else 1)
    elif command == "list-sessions":
        if not sessions: sys.exit(1)
        for key, data in sessions.items():
            fmt = option("-F")
            print(fmt.replace("#{session_path}", data["path"]).replace("#{session_name}", key))
    elif command == "display-message":
        print(sessions[target()]["path"])
    elif command == "new-session":
        assert "-d" in args or "-ds" in args, "new session must be detached"
        key = option("-s") or option("-ds")
        assert key not in sessions and key and not key.startswith("-") and not any(c in key for c in ".:\n")
        index = str(state["base"])
        sessions[key] = {"path": cwd(), "windows": {index: option("-n")}, "commands": [args[-1]]}
        if "-P" in args: print(index)
    elif command == "move-window":
        key = target()
        old = option("-s").split(":", 1)[1]
        new = option("-t").split(":", 1)[1]
        assert int(new) >= 1 and new not in sessions[key]["windows"]
        sessions[key]["windows"][new] = sessions[key]["windows"].pop(old)
    elif command == "list-windows":
        for index in sessions[target()]["windows"]: print(index)
    elif command == "new-window":
        key = target()
        index = option("-t").split(":", 1)[1]
        assert index.isdigit() and int(index) >= 1 and index not in sessions[key]["windows"], args
        assert int(index) > max(map(int, sessions[key]["windows"]))
        sessions[key]["windows"][index] = option("-n")
        sessions[key]["commands"].append(args[-1])
    elif command in ("select-window", "attach-session", "switch-client"):
        assert target() in sessions
        if command in ("attach-session", "switch-client"):
            assert len(sessions[target()]["windows"]) >= 3, "attached before windows exist"
            state["attached"] = [command, target()]
    else:
        raise AssertionError("Forbidden tmux command: " + str(args))
    file.write_text(json.dumps(state)); sys.exit(0)
if name == "fzf":
    data = sys.stdin.read()
    pathlib.Path(os.environ["FZF_INPUT"]).write_text(data)
    pathlib.Path(os.environ["FZF_ENV"]).write_text(json.dumps({k: os.getenv(k) for k in ("SHELL", "TW_BASH", "TW_SELF")}))
    print(data.splitlines()[0] + "\n" if os.getenv("FZF_FIRST") and data else os.getenv("FZF_OUTPUT", ""), end="")
    sys.exit(int(os.getenv("FZF_CODE", "0")))
if name == "find":
    if os.getenv("FAIL_FIND"): sys.exit(int(os.environ["FAIL_FIND"]))
    roots = args[:args.index("-mindepth")]
    assert args[len(roots):] == ["-mindepth", "1", "-maxdepth", "1", "-type", "d"]
    for root in roots:
        assert pathlib.Path(root).is_dir()
        for path in sorted(pathlib.Path(root).iterdir()):
            if path.is_dir(): print(path)
    sys.exit(0)
if name == "git":
    assert not any(a in args for a in ("remove", "prune", "fetch", "add")), args
    if "--git-common-dir" in args: print(os.environ["REPO"] + "/.git")
    elif "--porcelain" in args:
        if os.getenv("FAIL_GIT") == "list": sys.exit(23)
        path = os.environ["REPO"]
        if "-z" in args: print("worktree " + path + "\0branch refs/heads/main\0\0", end="")
        else: print("worktree " + (json.dumps(path) if any(c in path for c in '\\"\n\t') else path) + "\nbranch refs/heads/main\n")
    elif "for-each-ref" in args:
        if os.getenv("FAIL_GIT") == "refs": sys.exit(23)
        print("B\tmain\t\t")
    sys.exit(0)
if name == "pgrep": sys.exit(99)
if name in ("nvim", "shell ;'$(touch INJECTED)"):
    sys.exit(0)
if name in ("open", "xdg-open", "defaults"): sys.exit(0)
sys.exit(98)
'''


class SessionPortabilityTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(BASH, "Tests require Bash >= 4.0 (brew install bash)")
        temp = tempfile.TemporaryDirectory(prefix="session portability ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.home = self.root / "home with spaces"
        self.bin = self.root / "stub bin"
        self.copy = self.root / "scripts ;'$(touch INJECTED)"
        for p in (self.home, self.bin, self.copy):
            p.mkdir()
        self.log, self.state, self.input = (self.root / n for n in ("log", "state", "fzf-input"))
        self.env = {"HOME": str(self.home), "PATH": str(self.bin) + ":/usr/bin:/bin",
                    "SHELL": "/bin/bash", "LOG": str(self.log), "STATE": str(self.state),
                    "FZF_INPUT": str(self.input), "FZF_ENV": str(self.root / "fzf-env"), "LC_ALL": "C", "TW_ROOTS": str(self.home / "work"),
                    "TW_REPOS": str(self.home / "work/repo"), "PYTHONDONTWRITEBYTECODE": "1"}
        self.reset_state()
        for name in ("tmux", "fzf", "git", "find", "pgrep", "nvim", "defaults", "open", "xdg-open",
                     "shell ;'$(touch INJECTED)"):
            p = self.bin / name
            p.write_text("#!" + sys.executable + "\n" + STUB)
            p.chmod(0o755)
        for name in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            shutil.copy2(SCRIPTS / name, self.copy / name)
        self.repo = self.home / "work/repo"
        (self.repo / ".git").mkdir(parents=True)
        self.env["REPO"] = str(self.repo)

    def reset_state(self, base=0, sessions=None):
        self.state.write_text(json.dumps({"base": base, "sessions": sessions or {}}))
        if self.log.exists():
            self.log.unlink()

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def run_script(self, script="tmux-sessionizer", *args, code=0, bash=None):
        result = subprocess.run([bash or BASH, str(self.copy / script), *map(str, args)],
                                env=self.env, cwd=self.home, capture_output=True, text=True, timeout=15)
        self.assertEqual(code, result.returncode, result.stdout + result.stderr)
        self.assertFalse((self.home / "INJECTED").exists())
        return result

    def choose_worktree(self, path=None):
        path = path or self.repo
        self.env["FZF_OUTPUT"] = "\t".join(("wt", str(self.repo), str(path), "main", "", "fixture")) + "\n"

    def assert_new_session(self, path, inside=False, base=0):
        state = json.loads(self.state.read_text())
        self.assertEqual(1, len(state["sessions"]))
        name, session = next(iter(state["sessions"].items()))
        self.assertEqual(str(path), session["path"])
        self.assertEqual({str(max(base, 1) + i): n for i, n in enumerate(("editor", "server", "shell"))},
                         session["windows"])
        self.assertEqual(["switch-client" if inside else "attach-session", name], state["attached"])
        self.assertFalse(any(tool == "pgrep" for tool, _ in self.calls()))
        return session

    def test_detached_creation_then_attach_or_switch_and_no_window_zero(self):
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            for base, inside in ((0, False), (1, True), (7, False)):
                with self.subTest(script=script, base=base, inside=inside):
                    self.reset_state(base)
                    self.env["TMUX"] = "fixture" if inside else ""
                    if script.endswith(".sh"):
                        self.choose_worktree()
                        self.run_script(script)
                    else:
                        self.run_script(script, self.repo)
                    self.assert_new_session(self.repo, inside, base)

    def test_existing_session_is_preserved_entirely(self):
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            session = {"path": str(self.repo), "windows": {"2": "custom", "8": "user", "9": "extra"},
                       "commands": ["private"]}
            self.reset_state(sessions={"repo": session})
            self.choose_worktree()
            self.run_script(script, *(() if script.endswith(".sh") else (self.repo,)))
            self.assertEqual(session, json.loads(self.state.read_text())["sessions"]["repo"])
            commands = [args[0] for name, args in self.calls() if name == "tmux"]
            self.assertFalse(set(commands) & {"new-session", "new-window", "select-window", "move-window"})

    def test_invalid_directory_and_collision_refused(self):
        self.run_script("tmux-sessionizer", self.home / "missing", code=1)
        self.assertEqual({}, json.loads(self.state.read_text())["sessions"])
        elsewhere = self.home / "elsewhere"
        elsewhere.mkdir()
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            self.reset_state(sessions={"repo": {"path": str(elsewhere), "windows": {"1": "x"}, "commands": []}})
            before = self.state.read_text()
            self.choose_worktree()
            self.run_script(script, *(() if script.endswith(".sh") else (self.repo,)), code=1)
            self.assertEqual(before, self.state.read_text())

    def test_metacharacters_shell_and_paths_are_data(self):
        path = self.home / "-repo.foo:bar ;'$(touch INJECTED)"
        path.mkdir()
        shell = self.bin / "shell ;'$(touch INJECTED)"
        self.env["SHELL"] = str(shell)
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            self.reset_state()
            self.choose_worktree(path)
            self.run_script(script, *(() if script.endswith(".sh") else (path,)))
            session = self.assert_new_session(path)
            for command in session["commands"]:
                result = subprocess.run(["/bin/sh", "-c", command], cwd=self.home, env=self.env,
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(0, result.returncode, result.stderr)
            calls = self.calls()
            self.assertIn([shell.name, ["-i"]], calls)
            self.assertFalse((self.home / "INJECTED").exists())

    def test_missing_editor_and_invalid_shell_fall_back(self):
        (self.bin / "nvim").unlink()
        self.env["SHELL"] = str(self.home / "missing shell")
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            self.reset_state()
            self.choose_worktree()
            self.run_script(script, *(() if script.endswith(".sh") else (self.repo,)))
            session = self.assert_new_session(self.repo)
            self.assertNotIn("nvim", session["commands"][0])
            self.assertRegex(session["commands"][0], r"/bin/(zsh|bash)")

    def test_editor_failure_still_starts_interactive_shell(self):
        self.env["SHELL"] = str(self.bin / "shell ;'$(touch INJECTED)")
        (self.bin / "nvim").write_text("#!/bin/sh\nexit 23\n")
        self.run_script("tmux-sessionizer", self.repo)
        command = self.assert_new_session(self.repo)["commands"][0]
        result = subprocess.run(["/bin/sh", "-c", command], env=self.env, cwd=self.home, timeout=5)
        self.assertEqual(0, result.returncode)
        self.assertIn(["shell ;'$(touch INJECTED)", ["-i"]], self.calls())

    def test_default_roots_exist_and_override_handles_spaces(self):
        personal = self.home / "peter-projects/my project"
        personal.mkdir(parents=True)
        self.env["FZF_OUTPUT"] = str(personal)
        self.run_script()
        offered = self.input.read_text().splitlines()
        self.assertIn(str(personal), offered)
        self.assertIn(str(self.repo), offered)
        self.assert_new_session(personal)
        self.reset_state()
        self.env["TMUX_SESSIONIZER_ROOTS"] = str(personal.parent) + ":" + str(self.home / "absent")
        self.run_script()
        self.assertEqual([str(personal)], self.input.read_text().splitlines())

    def test_cancellation_harmless_but_picker_errors_propagate(self):
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            for status in (1, 130, 2):
                self.reset_state()
                self.env.update(FZF_CODE=str(status), FZF_OUTPUT="")
                self.run_script(script, code=0 if status in (1, 130) else 2)
                self.assertEqual({}, json.loads(self.state.read_text())["sessions"])

    def test_tmux_failures_propagate_without_attach(self):
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            for command in ("new-session", "move-window", "list-windows", "new-window", "select-window", "attach-session"):
                self.reset_state()
                self.env["FAIL_TMUX"] = command
                self.choose_worktree()
                self.run_script(script, *(() if script.endswith(".sh") else (self.repo,)), code=23)
                self.assertNotIn("attached", json.loads(self.state.read_text()))
        self.env.pop("FAIL_TMUX")

    def test_worktree_fzf_subprocesses_quote_script_path(self):
        self.choose_worktree()
        self.run_script("tmux-worktreeizer.sh")
        argv = next(args for tool, args in self.calls() if tool == "fzf")
        self.assertIn("--with-shell=/bin/sh -c", argv)
        exported = json.loads(Path(self.env["FZF_ENV"]).read_text())
        self.assertEqual(self.env["SHELL"], exported["SHELL"])
        self.assertEqual(BASH, exported["TW_BASH"])
        self.assertEqual(str(self.copy / "tmux-worktreeizer.sh"), exported["TW_SELF"])
        preview = argv[argv.index("--preview") + 1]
        result = subprocess.run(["/bin/sh", "-c", preview.replace("{1}", "new").replace("{2}", "'" + str(self.repo) + "'")
                                 .replace("{3}", "''").replace("{4}", "''")],
                                env={**self.env, "TW_BASH": BASH, "TW_SELF": str(self.copy / "tmux-worktreeizer.sh")}, cwd=self.home,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("create a new worktree", result.stdout)
        for i, arg in enumerate(argv):
            if arg == "--bind":
                self.assertNotIn(str(self.copy), argv[i + 1])
        env = self.env.copy()
        env.update(TW_BASH=BASH, TW_SELF=str(self.copy / "tmux-worktreeizer.sh"))
        env["TW_STATE"] = str(self.home / "state with spaces")
        Path(env["TW_STATE"]).mkdir()
        result = subprocess.run([BASH, str(self.copy / "tmux-worktreeizer.sh"), "--view-enter", "repo", str(self.repo)],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotIn(str(self.copy), result.stdout)

    def test_worktree_cache_mtime_is_portable(self):
        cache = self.home / ".cache/tmux-worktreeizer"
        cache.mkdir(parents=True)
        file = cache / ("pr" + str(self.repo).replace("/", "_").replace(" ", "_") + ".tsv")
        file.write_text("")
        gh = self.bin / "gh"
        gh.write_text("#!/bin/sh\nprintf called >> \"$HOME/GH_CALLED\"\n")
        gh.chmod(0o755)
        (self.repo / ".git/worktrees/extra").mkdir(parents=True)
        self.env.update(FZF_CODE="130", FZF_OUTPUT="")
        stat = self.bin / "stat"
        for mode in ("GNU", "BSD"):
            stat.write_text("#!" + sys.executable + "\nimport os, sys\n"
                            + "if sys.argv[1:3] != " + repr(["-c", "%Y"] if mode == "GNU" else ["-f", "%m"])
                            + ": sys.exit(2)\nprint(int(os.stat(sys.argv[3]).st_mtime))\n")
            stat.chmod(0o755)
            result = self.run_script("tmux-worktreeizer.sh")
            self.assertNotIn("stat:", result.stderr)
            self.assertFalse((self.home / "GH_CALLED").exists())

    def test_worktree_url_opener_uses_available_command(self):
        url = "https://example.invalid/pr/1?x=one&y=two"
        self.run_script("tmux-worktreeizer.sh", "--open-pr", url)
        self.assertIn(["open", [url]], self.calls())
        limited = self.root / "limited bin"
        limited.mkdir()
        for name in ("basename", "dirname"):
            tool = shutil.which(name, path="/usr/bin:/bin")
            self.assertIsNotNone(tool)
            (limited / name).symlink_to(tool or "")
        (limited / "xdg-open").symlink_to(self.bin / "xdg-open")
        self.env["PATH"] = str(limited)
        self.log.unlink()
        self.run_script("tmux-worktreeizer.sh", "--open-pr", url)
        self.assertIn(["xdg-open", [url]], self.calls())

    def test_new_worktree_picker_cancels_without_mutation_and_propagates_errors(self):
        self.env["TW_NO_FETCH"] = "1"
        for status in (1, 130, 2):
            self.reset_state()
            self.env.update(FZF_CODE=str(status), FZF_OUTPUT="")
            self.run_script("tmux-worktreeizer.sh", "--new", self.repo, code=0 if status in (1, 130) else 2)
            self.assertEqual({}, json.loads(self.state.read_text())["sessions"])
            self.assertIn("--with-shell=/bin/sh -c", next(args for name, args in self.calls() if name == "fzf"))

    def test_worktree_existing_custom_session_with_backslash_path_is_preserved(self):
        path = self.home / "literal\\t backslash"
        path.mkdir()
        session = {"path": str(path), "windows": {"1": "a", "3": "b", "9": "c"}, "commands": ["private"]}
        self.reset_state(sessions={"custom-session": session})
        self.choose_worktree(path)
        self.run_script("tmux-worktreeizer.sh")
        state = json.loads(self.state.read_text())
        self.assertEqual({"custom-session": session}, state["sessions"])
        self.assertEqual(["attach-session", "custom-session"], state["attached"])

    def test_lookup_failures_do_not_create_sessions(self):
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            commands = ["has-session"] + (["list-sessions"] if script.endswith(".sh") else [])
            for command in commands:
                self.reset_state()
                self.env["FAIL_TMUX"] = command
                self.choose_worktree()
                self.run_script(script, *(() if script.endswith(".sh") else (self.repo,)), code=23)
                self.assertEqual({}, json.loads(self.state.read_text())["sessions"])

    def test_newline_directory_and_symlink_target_are_explicitly_refused(self):
        path = self.home / "newline\n"
        path.mkdir()
        alias = self.home / "safe alias"
        alias.symlink_to(path, target_is_directory=True)
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            self.reset_state()
            self.choose_worktree(alias)
            self.run_script(script, *(() if script.endswith(".sh") else (path,)), code=1)
            self.assertEqual({}, json.loads(self.state.read_text())["sessions"])

    def test_tmux_format_characters_in_paths_remain_literal(self):
        path = self.home / "repo #{session_name} ## #(touch INJECTED)"
        path.mkdir()
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            self.reset_state()
            self.choose_worktree(path)
            self.run_script(script, *(() if script.endswith(".sh") else (path,)))
            self.assert_new_session(path)
            for name, args in self.calls():
                if name == "tmux" and args[0] == "new-window":
                    self.assertEqual(str(path).replace("#", "##"), args[args.index("-c") + 1])

    def test_worktree_listing_preserves_git_quoted_paths_without_manual_selection(self):
        repo = self.home / 'work/repo" literal\\t #{session_name}'
        (repo / ".git").mkdir(parents=True)
        self.repo = repo
        self.env.update(REPO=str(repo), TW_REPOS=str(repo), TW_ROOTS=str(repo.parent), FZF_FIRST="1")
        self.run_script("tmux-worktreeizer.sh")
        self.assert_new_session(repo)
        porcelain = [args for tool, args in self.calls() if tool == "git" and "--porcelain" in args]
        self.assertTrue(porcelain)
        self.assertTrue(all("-z" in args for args in porcelain))

    def test_worktree_listing_errors_propagate_even_when_fzf_has_no_selection(self):
        for failure in ("list", "refs", "tmux"):
            for fzf_status in (0, 1, 130):
                self.reset_state()
                self.env.update(FZF_OUTPUT="", FZF_CODE=str(fzf_status))
                if failure == "tmux":
                    self.env["FAIL_TMUX"] = "list-sessions"
                else:
                    self.env["FAIL_GIT"] = failure
                self.run_script("tmux-worktreeizer.sh", code=23)
                self.assertEqual({}, json.loads(self.state.read_text())["sessions"])
                self.env.pop("FAIL_TMUX", None)
                self.env.pop("FAIL_GIT", None)

    def test_directory_search_failures_are_not_confused_with_cancellation(self):
        for status in (1, 23):
            for picker_status in (0, 1, 130):
                self.reset_state()
                self.env.update(FAIL_FIND=str(status), FZF_CODE=str(picker_status), FZF_OUTPUT="")
                self.run_script("tmux-sessionizer", code=2 if status == 1 else status)
                self.assertEqual({}, json.loads(self.state.read_text())["sessions"])
        self.reset_state()
        self.env.update(FAIL_FIND="141", FZF_CODE="130", FZF_OUTPUT="")
        self.run_script("tmux-sessionizer")
        self.assertEqual({}, json.loads(self.state.read_text())["sessions"])

    def test_sessionizer_runs_with_system_bash_and_empty_roots_are_harmless(self):
        self.run_script("tmux-sessionizer", self.repo, bash="/bin/bash")
        self.assert_new_session(self.repo)
        self.reset_state()
        empty_home = self.root / "empty home"
        empty_home.mkdir()
        self.env["HOME"] = str(empty_home)
        self.run_script("tmux-sessionizer", bash="/bin/bash")
        self.assertEqual([], self.calls())

    def test_syntax_and_worktree_bash_minimum(self):
        for script in ("tmux-sessionizer", "tmux-worktreeizer.sh"):
            result = subprocess.run([BASH, "-n", str(self.copy / script)], capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
        if int(subprocess.check_output(["/bin/bash", "-c", "printf '%s' \"${BASH_VERSINFO[0]}\""]).decode()) < 4:
            result = self.run_script("tmux-worktreeizer.sh", "--help", code=1, bash="/bin/bash")
            self.assertIn("Bash 4.0", result.stderr)
        text = (self.copy / "tmux-worktreeizer.sh").read_text()
        removal = text[text.index("do_remove() {"):text.index("# ---------------------------------------------------------------- ui")]
        self.assertIn('read -rp "remove it? [y/N] "', removal)
        self.assertIn('worktree remove --force --force "$path"', removal)
        session_code = text[text.index("open_session() {"):text.index("# ---------------------------------------------------------------- create")]
        self.assertNotIn("do_remove", session_code)
        self.assertNotIn("kill-session", session_code)


if __name__ == "__main__":
    unittest.main()
