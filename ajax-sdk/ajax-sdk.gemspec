# frozen_string_literal: true

require_relative 'lib/ajax/sdk/version'

Gem::Specification.new do |spec|
  spec.name = 'ajax-sdk'
  spec.version = Ajax::Sdk::VERSION
  spec.authors = ['Jonathan PHILIPPE']
  spec.email = ['pretrine@gmail.com']

  spec.summary = 'Unofficial Ruby SDK for Ajax alarm systems'
  spec.description = 'SIA DC-09 event receiver for Ajax hubs on the local network, and client for the Ajax cloud ' \
                     'used by the official app: devices with battery and signal, arming, history, live streams.'
  spec.homepage = 'https://github.com/jplot/koti/tree/main/ajax-sdk'
  spec.license = 'MPL-2.0'
  # grpc and google-protobuf ship precompiled binaries only up to Ruby 3.4; the rest of koti stays on 4.0.
  spec.required_ruby_version = ['>= 3.4', '< 4.0']

  spec.add_dependency 'google-protobuf', '~> 4.36'
  spec.add_dependency 'grpc', '~> 1.85'
  spec.add_dependency 'rotp', '~> 6.3'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/jplot/koti/tree/main/ajax-sdk'
  spec.metadata['changelog_uri'] = 'https://github.com/jplot/koti/blob/main/ajax-sdk/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = IO.popen(%w[git ls-files -z --cached --others --exclude-standard], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |file|
      file.start_with?('lib/', 'sig/') || %w[README.md CHANGELOG.md LICENSE].include?(file)
    end
  end
  spec.require_paths = ['lib']
end
