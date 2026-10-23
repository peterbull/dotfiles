require 'steep'
require 'rbs/inline'
require 'rbs/inline/cli'
require 'stringio'
require 'fileutils'

mode, root = ARGV
abort 'usage: server.rb (langserver|generate) PROJECT_ROOT' unless %w[langserver generate].include?(mode) && root
root = Pathname(root).realpath
steepfile = root.join('.ruby-lsp/Steepfile')
project = Steep::Project.new(steepfile_path: steepfile)
Steep::Project::DSL.parse(project, steepfile.read, filename: steepfile.to_s)
files = project.targets.flat_map { |target| target.source_pattern.patterns }.flat_map do |pattern|
  Dir.glob(project.absolute_path(pattern)).map { |path| Pathname(path).relative_path_from(root).to_s }
end
output = project.base_dir.join('rbs/generated')
FileUtils.mkdir_p(output)
File.open(output.join('.generation.lock'), File::RDWR | File::CREAT, 0600) do |lock|
  lock.flock(File::LOCK_EX)
  Dir.chdir(root) do
    status = RBS::Inline::CLI.new(stdout: StringIO.new, stderr: STDERR).run(["--output=#{output}", *files])
    abort 'RBS generation failed' unless status.zero?
  end

  Dir.glob(output.join('**/*.rbs')).each do |path|
    _, _, declarations = RBS::Parser.parse_signature(File.read(path))
    classes = Hash.new { |hash, key| hash[key] = [] }
    collect = lambda do |decls, namespace|
      decls.grep(RBS::AST::Declarations::Class).each do |decl|
        name = "#{namespace}::#{decl.name}"
        classes[name] << decl
        collect.call(decl.members, name)
      end
    end
    collect.call(declarations, '')
    classes.each_value do |parts|
      methods = parts.flat_map(&:members).grep(RBS::AST::Members::MethodDefinition)
      initializer = methods.find { |method| method.kind == :instance && method.name == :initialize }
      next unless initializer

      # Struct's generated constructor must honor a custom initializer's required keywords.
      methods.select { |method| method.kind == :singleton && method.name == :new }.each do |constructor|
        constructor.overloads.replace(initializer.overloads.map do |overload|
          type = overload.method_type
          overload.update(method_type: type.update(type: type.type.with_return_type(RBS::Types::Bases::Instance.new(location: nil))))
        end)
      end
    end
    temporary = "#{path}.tmp"
    File.open(temporary, 'w') { |io| RBS::Writer.new(out: io).write(declarations) }
    File.rename(temporary, path)
  end
end

if mode == 'langserver'
  Dir.chdir(root)
  # Steep 2.1 sends an unsolicited UUID response to didOpen; Neovim expects its own numeric IDs.
  adapter = Module.new do
    def finish_type_check(request)
      request.needs_response = false if request.guid.is_a?(String) && request.guid.match?(/\A[0-9a-f-]{36}\z/)
      super
    end
  end
  Steep::Server::Master.prepend(adapter)
  ARGV.replace(['langserver', "--steepfile=#{steepfile}", '-j', '1', '--no-command-socket'])
  load Gem.bin_path('steep', 'steep')
end
