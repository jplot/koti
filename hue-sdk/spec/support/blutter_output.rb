# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# A directory laid out like blutter's output, holding the given files.
module BlutterOutput
  def blutter_output(files)
    Dir.mktmpdir.tap do |directory|
      files.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(directory, path)))
        File.write(File.join(directory, path), content)
      end
    end
  end
end

RSpec.configure { |config| config.include BlutterOutput }
