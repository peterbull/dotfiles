# Mac dotfiles

This repository currently lives at `$HOME`. Do not clone over an existing home
or symlink the entire `.config` directory. The baseline bootstrap supports a
separate source checkout, but deploys **only two VS Code files**. Installing
packages is not the same as deploying the remaining home-root configuration.

Phases 1–4 are implemented, tested and independently reviewed. **All 146 fixture
tests passed with no skips**, with monitored sources unchanged during execution.
The complete home-Mac restore
and normal editor startup have not been tested. No live package installations,
service starts, commits or pushes were performed during this work.

## Restoration order

1. Review the destination's macOS/architecture and Homebrew support. Tinycast
   currently requires macOS 26. Install Apple developer tools and Homebrew
   separately. Follow Homebrew's PATH instructions; do not assume its prefix.
2. Bring the reviewed configuration into the existing home-root checkout.
   Preserve conflicting local settings and private files. No command here
   overwrites or deploys the entire home directory.
3. Preview the shared package and VS Code plans:

   ```sh
   bash "$HOME/dotfiles/scripts/bootstrap-mac" --dry-run
   ```

4. After reviewing `Brewfile`, explicitly install the baseline if wanted:

   ```sh
   bash "$HOME/dotfiles/scripts/bootstrap-mac" --install
   ```

5. Preview optional restoration. Select only the groups you need:

   ```sh
   /usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional"
   /usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --feature shell --feature tmux
   ```

6. Explicitly apply selected groups. Install runtimes before optional Node CLI
   tools; the Node-tools preflight requires an already installed managed Node:

   ```sh
   /usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --apply --feature runtimes
   /usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --apply --feature shell --feature tmux --feature provider
   /usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --apply --feature editor
   /usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --apply --feature node-tools
   ```

7. Run read-only checks, then validate the real setup on the destination Mac.
   Start a new terminal/editor yourself after reviewing configuration changes.
   Neither installer reloads your running tmux server or starts CTM.

   ```sh
   bash "$HOME/dotfiles/scripts/dotfiles-doctor"
   /usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --check
   ```

The scripts use their own locations to resolve source manifests. Optional
provisioning requires canonical, existing, absolute `HOME`; macOS temporary
aliases such as `/var` versus `/private/var` must be resolved in test fixtures.
Bob actions use an explicit helper-owned configuration under
`~/.local/state/dotfiles-bob/`; an existing user Bob configuration is not read or
rewritten. Writable selection/proxy files reject symlinks, as do managed paths.

## Installation owners

| Owner | Shared or optional tools |
| --- | --- |
| Homebrew | Bash, Git tools, tmux, fzf, search tools, managers, shell plugins, Ghostty, Nerd Font, Tinycast |
| Bob | Neovim `0.11.7`; no separate Brew Neovim |
| mise | Global Node `24` and Ruby `3.4.9`; project selectors remain authoritative |
| uv | Separate Python `3.12.13` provider venv with `pynvim==0.6.0`; project Python remains separate |
| Explicit Git pins | Oh My Zsh, TPM and selected tmux plugins; optional editor checkouts |
| Mason/project/toolchains | Language servers, formatters and debug adapters; Ruby tools remain project gems |
| Managed Node/Corepack/pnpm | Optional Pi `1.0.4` and Bruno CLI `4.0.0`, using pnpm `12.3.4` |

Brewfiles express package intent, not a complete version lock. Adding a package
can change dependencies even with `--no-upgrade`. Preserve the existing work
Mac's standalone uv and manually installed apps; inventory differences are not
permission to relink or reinstall them.

## Baseline bootstrap and VS Code

No arguments or `--dry-run` are read-only previews. `--install` installs only
`Brewfile` with `--no-upgrade`. Automatic Brew updates, analytics and install-time
cleanup are disabled; inherited Bundle cleanup options are cleared. It does not
install Homebrew, activate runtimes, install the work profile or start services.

Close VS Code before deploying its two reviewed files:

```sh
bash "$HOME/dotfiles/scripts/bootstrap-mac" --link-vscode
bash "$HOME/dotfiles/scripts/bootstrap-mac" --link-vscode --backup
```

Correct links are no-ops. Conflicting regular files or symlink objects require
`--backup`; originals move intact into unique mode-`0700` directories under
`~/Library/Application Support/dotfiles-backups/`. These private backups are
ignored. Preserve them securely; do not add settings backups to Git.

Directories, directory-resolving links, special objects and symlinked ancestors
are refused even with backup permission. All selected actions are preflighted;
targets are rechecked before mutation. Failures preserve completed actions and
backups rather than deleting data for an automatic rollback. Restore an original
manually only after closing the affected app and reviewing the generated link.

Install/link modes can be combined. `--backup` requires `--link-vscode`;
`--dry-run` cannot accompany mutating flags. Unknown/incompatible flags exit 2.

## Optional provisioning

`provision-optional` previews by default. `--apply` requires explicit, repeatable
`--feature` arguments. `--check` reads local checkout/provider/Mason metadata;
it does not execute Python providers or plugins and does not establish health.
Existing checkout contents remain untouched; dirty/untracked content verification
is deliberately omitted where it could execute repository-defined filters.

| Feature | Scope |
| --- | --- |
| `shell` | Pinned Oh My Zsh; enabled OMZ plugins are bundled |
| `tmux` | Pinned TPM, sensible, resurrect and fingers; clone only, no TPM execution/reload |
| `provider` | Isolated uv Python provider at `~/.virtualenvs/nvim` |
| `editor` | Optional pinned local notebook/grammar source checkouts |
| `runtimes` | Explicit mise installation and Bob installation/activation |
| `node-tools` | Optional pinned global CLI packages; requires installed managed Node/Corepack |
| `work` | Additive `Brewfile.work`; no services or forced links |

Existing checkouts are preserved, including dirty/untracked work and differing
revisions. No pull, reset or checkout is performed on an existing destination.
Fresh destinations use full commit pins from `provisioning.json`. Pins describe
source versions, not proven runtime builds. Unexpected directories, special
objects and symlinked destination ancestors are refused.

Existing provider environments are not adopted or overwritten. Repeated setup
requires the helper's matching ownership marker and expected environment/package
metadata. A failure can leave a preserved, unowned partial environment; inspect
it manually before deciding how to recover. Never delete a venv automatically
or copy one between Macs.

Node CLI provisioning does not restore Pi credentials, provider settings, skills
or extensions; those belong to the separate `pi-config` setup. Corepack is
invoked directly; no global pnpm shim is created or enabled. Shared commands can
use `mise --no-config exec node@24 -- corepack pnpm@12.3.4 ...`; use a project's
own declared pnpm version for that project's work. Seven-day package
age policy is declared in `dotfiles/pnpm-workspace.yaml` and installer arguments.
Dependency scripts are disabled. Native CLI functionality and package-manager
installation on the destination still require validation; do not blindly approve
all blocked build scripts.

## Shell and sessions

The zsh configuration resolves Homebrew dynamically and activates mise once.
Optional prompt/completion tools are guarded. Node/Ruby startup no longer loads
competing NVM/asdf/RVM managers; installed legacy data remains untouched. Optional
pyenv remains guarded for legacy Python workflows. Existing project selectors
can differ from the global defaults. The checked CTM/pool and local development
repositories use compatible selectors. Other `nvm` workflows were not verified.
Legacy `.nvmrc`/`.node-version` selection requires explicitly enabling mise's
`idiomatic_version_file_enable_tools = ["node"]` setting; this was not added to
the existing global configuration.

`bin/rvm` keeps legacy `rvm <version> do <command>` calls on mise. Administrative
commands use an existing HOME-relative RVM binary or report its absence. Private
secrets/signing includes and aliases are preserved. Optional, ignored overrides
can live in `~/.config/zsh/work.local.zsh` and `~/.zshrc.local`; they are not copied
or created by the installers.

The sessionizer searches only existing roots. Override roots with a colon-separated
`TMUX_SESSIONIZER_ROOTS`, or pass one explicit directory. Cancelled selection is
harmless. New sessions are populated detached before attachment; existing sessions
are preserved. Shell fallback does not require Fish. Tab/newline paths and session
name collisions are refused rather than interpreted as commands.

The worktreeizer requires **Bash 4 or newer**, supplied by the shared Brewfile;
macOS Bash 3.2 remains sufficient for the baseline bootstrap and sessionizer.
Its interactive create/remove workflows remain explicit user actions. Validation
uses stubs, not your live server or repositories.

## Neovim and local development checkouts

Missing provider, notebook checkout or custom parser sources are intentionally
optional. The provider is not a notebook kernel. Active notebooks use uv overlays
with `jupyter_client`/`ipykernel` and project environments. The old
`.setup/molten-nvim.sh` is not used; ImageMagick/Cairo/TeX are not notebook baseline
requirements.

The current `nvim-jupyter` working tree contains unpublished changes, including
required untracked modules. Its committed pin cannot reproduce that customized
working tree. It remains untouched. Publishing those changes needs a separate
commit/push request.

Mustache query contents preserve the current local customization as regular
tracked files, not absolute symlinks. Previous query-link objects are preserved
in a private backup. Grammar sources and compiled parsers remain separate
prerequisites. After restoring the grammar checkout, install its parser with
`:TSInstall mustache` on the destination, using that Mac's Apple developer tools.
Reef's unavailable grammar is disabled safely; no replacement query or repository
was invented.

Active LSP configurations are applied before explicit Mason enablement; disabled
entries are excluded. Formatter and adapter installation ownership is explicit.
The configured debugger group is installed by default to preserve existing
intent. Set `vim.g.dotfiles_dap_tools = false` before LSP loads to skip its
installation; existing tools are not removed. Real adapter availability still
requires validation. Missing adapters produce launch-time errors, not startup failures. Rust/Zig
helpers use HOME-relative paths and are optional. Compilers stay toolchain-owned.
Markdown dependency setup also invokes Corepack directly with managed Node 24,
pinned pnpm and strict seven-day age checks. It requires the runtime feature, not
a pre-existing global pnpm command; native dependency scripts remain blocked.

## Optional CTM/work profile

Review `Brewfile.work` before applying it:

```sh
/usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --feature work
/usr/bin/python3 -B "$HOME/dotfiles/scripts/provision-optional" --apply --feature work
```

It declares CTM native/media dependencies and OpenResty ingress separately from
the shared baseline. It does not install host database servers, start services,
force links, or invoke `ctmstart`/`ctmstop`. Select Docker Desktop **or** OrbStack
separately; authentication and project runtime installation are manual concerns.

Percona Toolkit is excluded because it pulls another MySQL client family.
Brewed Mailcatcher is excluded because it pulls another Ruby. Legacy Yarn,
unproven extra Lua tools and ngrok are not included automatically.

## Verification and limits

```sh
/usr/bin/python3 -B -m unittest discover -s "$HOME/dotfiles/tests" -p 'test_*.py'
bash "$HOME/dotfiles/scripts/dotfiles-doctor" --brew-check
```

Tests use temporary homes, fake commands and minimal isolated Neovim with plugin
stubs. Missing Bob is reported as skipped editor checks, not an import failure
or proof of editor readiness. Provision the runtime first, or select an explicit
binary with `DOTFILES_TEST_NVIM=/absolute/path/to/nvim`. They must not source real private files, start the real editor or install
packages. The doctor distinguishes base failures from optional warnings; exit 0
is **not** complete editor readiness. Git/uv/Ghostty/font inventory differences
on the work Mac were previously observed and intentionally not corrected by
automatic installs.

The nine previously staged files remain unchanged in the Git index. New work is
unstaged for review. Narrow ignore exceptions cover only approved restoration
inputs; secrets, local overrides, virtualenvs, histories, backups and test caches
remain excluded. Ignore rules are not a secret scanner.

See [`PORTABILITY-PLAN.md`](PORTABILITY-PLAN.md) for approval and verification
evidence. The live work-Mac doctor returned zero base errors and 20 optional/editor
warnings, including intentionally unstaged restoration inputs and missing optional
setup. Both installer previews exited successfully without effects. Destination architecture compatibility, real plugin/adapter builds,
normal shell/editor startup and identity/signing remain unverified. Git signing
still needs separately configured 1Password and private identity assets; no
signing policy was weakened or private material copied.
