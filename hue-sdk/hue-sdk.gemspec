# frozen_string_literal: true

require_relative 'lib/hue/sdk/version'

Gem::Specification.new do |spec|
  spec.name = 'hue-sdk'
  spec.version = Hue::Sdk::VERSION
  spec.authors = ['Jonathan PHILIPPE']
  spec.email = ['pretrine@gmail.com']

  spec.summary = 'Unofficial Ruby SDK for the Philips Hue CLIP API v2'
  spec.description = 'Local-only client for a Philips Hue bridge: CLIP v2 resources, events, entertainment.'
  spec.homepage = 'https://github.com/jplot/koti/tree/main/hue-sdk'
  spec.license = 'MPL-2.0'
  spec.required_ruby_version = '>= 4.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/jplot/koti/tree/main/hue-sdk'
  spec.metadata['changelog_uri'] = 'https://github.com/jplot/koti/blob/main/hue-sdk/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = IO.popen(%w[git ls-files -z --cached --others --exclude-standard], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |file|
      file.start_with?('lib/', 'sig/') || %w[README.md CHANGELOG.md LICENSE].include?(file)
    end
  end
  spec.require_paths = ['lib']
end
