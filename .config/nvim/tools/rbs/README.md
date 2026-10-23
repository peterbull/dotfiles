# Inline RBS in Neovim

Ruby LSP provides the normal Ruby/Rails features. Steep 2.1 supplies type hover,
completion and definitions for opt-in files with `# rbs_inline: enabled` and a
project-local `.ruby-lsp/Steepfile`. The CTM pilot covers State, Source, Listener
and Stream. Its Ruby diagnostics are disabled until Rails/provider signatures
are available; this is editor assistance, not a complete application type check.

Install the pinned tooling bundle with mise and `bundle install --gemfile` for
this directory's Gemfile. It is separate from the application's bundle.

State and Source use Steep's native inline parser. The ordinary `check` sources
in Steepfile are passed to rbs-inline for Data/Struct fields; generated signatures
are refreshed on save. Use nested constant assignments inside their owner class
because rbs-inline 0.14 does not expand qualified constant-path assignments.
The launcher corrects generated constructors from explicit initializer types.

`K` displays an annotation directly on attr/Data/Struct field declarations;
on expressions it uses the attached language servers. No annotations are copied
by hand into the generated signatures.

The launcher contains a local workaround for Steep 2.1 sending a response with
an unsolicited UUID after didOpen. Only this Neovim process uses the adapter;
installed gems are unchanged. Command-socket access is disabled for this pilot.
