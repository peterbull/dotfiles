# Local Sorbet support for inline RBS

Neovim loads `lua/config/sorbet.lua` alongside Ruby LSP. Projects with a
`sorbet/config` use their own compiler bundle and configuration. Phonetrac's
capture profile below is a fallback for older checkouts without that config.
Sorbet attaches only to the source paths listed in that configuration. Opening
an unrelated file can crash Sorbet when its input directory is narrower than
the project root. `# typed: true` and RBS annotations do not add a file to the
configured source paths; outside them, Ruby LSP supplies hover information.

Ruby LSP and Sorbet run through `mise exec` from the project root. Ruby LSP
resolves its executable through RubyGems so a Mason wrapper cannot select an
older Ruby. Install its gems for each Ruby version used by your projects:

```sh
mise exec -- gem install ruby-lsp ruby-lsp-rails --no-document
```

Treesitter installs both Ruby and RBS parsers. The Ruby injection query in
`after/queries/ruby/injections.scm` joins consecutive `#:` / `#|` lines and
excludes their prefixes, so multiline signatures receive RBS highlighting.
Sorbet diagnostics from the project configuration are shown without filtering.

The fallback compiler bundle and `phonetrac.config` live here. Cache files go under
Neovim's cache directory, separately for each checkout. The fallback needs no
Sorbet configuration, RBI file, or compiler dependency in the project.

The fallback profile checks the capture module with Prism, experimental RBS comment
support and one worker thread. It skips gem RBIs and suppresses missing-context
codes 5002/7003. It provides editor types rather than a full Rails type check.
Watchman is disabled for the separate input paths; run `:lsp restart sorbet`
after external file changes such as switching branches. Unsaved editor changes
update types normally.

From a current phonetrac checkout, check types with:

```sh
SRB_SKIP_GEM_RBIS=1 mise exec -- bundle exec srb tc
```

For an older checkout without `sorbet/config`, use the fallback:

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
