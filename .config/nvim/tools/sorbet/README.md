# Local Sorbet support for inline RBS

Neovim loads `lua/config/sorbet.lua` alongside Ruby LSP. A project with a
Gemfile and `app/classes/live_conversation_capture/state.rb` uses this local
profile, including other phonetrac worktrees. Other projects can still opt in
with their own `sorbet/config`.

The compiler bundle and `phonetrac.config` live here. Cache files go under
Neovim's cache directory, separately for each checkout. Phonetrac needs no
Sorbet configuration, RBI file, or compiler dependency in its Gemfile.

The profile checks the capture module with Prism, experimental RBS comment
support and one worker thread. It skips gem RBIs and suppresses missing-context
codes 5002/7003. It provides editor types rather than a full Rails type check.
Watchman is disabled for the separate input paths; run `:LspRestart sorbet`
after external file changes such as switching branches. Unsaved editor changes
update types normally.

From a phonetrac checkout, check types with:

```sh
SRB_SKIP_GEM_RBIS=1 mise exec -- bundle exec \
  --gemfile "$HOME/.config/nvim/tools/sorbet/Gemfile" \
  srb tc --no-config @"$HOME/.config/nvim/tools/sorbet/phonetrac.config"
```

Append `--lsp` for an LSP client. Install the pinned tooling bundle if needed:

```sh
mise exec -- bundle install --gemfile "$HOME/.config/nvim/tools/sorbet/Gemfile"
```

Keep types beside their Ruby implementations:

```ruby
# typed: true
class Example
  #: String
  attr_reader :name

  #: (name: String) -> void
  def initialize(name:)
    @name = name
  end
end
```

Use `#|` for multiline method signatures. `@rbs name: Type` documentation is
not a Sorbet method signature. `K` uses native hover; Sorbet displays RBS
`String?` as `T.nilable(String)`. Add source paths to `phonetrac.config` when
expanding the profile. No generated record signatures are needed for ordinary
classes with explicitly typed accessors and constructors.
