# frozen_string_literal: true

require 'fileutils'
require_relative 'generate/model'
require_relative 'generate/ruby'
require_relative 'generate/rbs'
require_relative 'generate/index'

module Schema
  # Writes the typed values of the cloud messages, Ruby and RBS, from the schemas lib/ajax/sdk/cloud/schemas/ ships.
  module Generate
    SCHEMAS = 'lib/ajax/sdk/cloud/schemas'
    RUBY = 'lib/ajax/sdk/cloud/messages'
    RBS = 'sig/ajax/sdk/cloud/messages'

    module_function

    # @param root [String] the gem directory
    # @return [Array<String>] the files written, relative to +root+
    def write(root)
      [RUBY, RBS].each { FileUtils.rm_rf(File.join(root, it)) }
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
      model = Model.load(File.join(root, SCHEMAS))
      files = model.files.flat_map do |proto|
        stem = proto.delete_suffix('.proto')
        [["#{RUBY}/#{stem}.rb", Ruby.file(model, proto)], ["#{RBS}/#{stem}.rbs", Rbs.file(model, proto)]]
      end
      files.to_h.merge("#{RUBY}.rb" => Index.ruby(model), "#{RBS}.rbs" => Index.rbs(model))
    end

    def written(root)
      paths = [RUBY, RBS].flat_map { Dir.glob("#{it}/**/*", base: root) } + ["#{RUBY}.rb", "#{RBS}.rbs"]
      paths.select { File.file?(File.join(root, it)) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "wrote #{Schema::Generate.write(ARGV.first || File.expand_path('..', __dir__)).size} files"
end
