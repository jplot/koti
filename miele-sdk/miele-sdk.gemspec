# frozen_string_literal: true

require_relative 'lib/miele/sdk/version'

Gem::Specification.new do |spec|
  spec.name = 'miele-sdk'
  spec.version = Miele::Sdk::VERSION
  spec.authors = ['Jonathan PHILIPPE']
  spec.email = ['pretrine@gmail.com']

  spec.summary = 'Unofficial Ruby SDK for Miele@home appliances on the local network'
  spec.description = 'Local-only client for Miele@home appliances: discovery, state, commands, DOP2, pushed events.'
  spec.homepage = 'https://github.com/jplot/koti/tree/main/miele-sdk'
  spec.license = 'MPL-2.0'
  spec.required_ruby_version = '>= 4.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/jplot/koti/tree/main/miele-sdk'
  spec.metadata['changelog_uri'] = 'https://github.com/jplot/koti/blob/main/miele-sdk/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = IO.popen(%w[git ls-files -z --cached --others --exclude-standard], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |file|
      file.start_with?('lib/', 'sig/') || %w[README.md CHANGELOG.md LICENSE].include?(file)
    end
  end
  spec.require_paths = ['lib']
end
