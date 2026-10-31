# frozen_string_literal: true

require 'fileutils'
require_relative 'generate/model'
require_relative 'generate/ruby'
require_relative 'generate/rbs'
require_relative 'generate/index'

module Schema
  # Writes the typed values of the DOP2 and Dop1 objects, Ruby and RBS, from lib/miele/sdk/objects/objects.json.gz.
  module Generate
    OBJECTS = 'lib/miele/sdk/objects/objects.json.gz'
    RUBY = 'lib/miele/sdk/objects'
    RBS = 'sig/miele/sdk/objects'

    module_function

    # @param root [String] the gem directory
    # @return [Array<String>] the files written, relative to +root+
    def write(root)
      written(root).each { File.delete(File.join(root, it)) }
      sources(root).each do |path, source|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), source)
      end.keys
    end

    # @param root [String] the gem directory
    # @return [Array<String>] the generated files a fresh {write} would add, remove or change, relative to +root+
    def check(root)
      expected = sources(root)
      present = written(root)
      (expected.keys | present).sort.reject do |path|
        present.include?(path) && expected[path] == File.read(File.join(root, path))
      end
    end

    def sources(root)
      model = Model.load(File.join(root, OBJECTS))
      files = Index.top_level(model).flat_map do |item|
        path = Index.path(item)
        [["#{RUBY}/#{path}.rb", Ruby.file(model, item)], ["#{RBS}/#{path}.rbs", Rbs.file(model, item)]]
      end
      files.to_h.merge("#{RUBY}/families.rb" => Index.ruby(model), "#{RBS}/families.rbs" => Index.rbs(model))
    end

    # The family directories hold only generated files; objects.json.gz sits beside them.
    def written(root)
      paths = [RUBY, RBS].flat_map { Dir.glob("#{it}/*/**/*", base: root) }
      [*paths, "#{RUBY}/families.rb", "#{RBS}/families.rbs"].select { File.file?(File.join(root, it)) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "wrote #{Schema::Generate.write(ARGV.first || File.expand_path('..', __dir__)).size} files"
end
