# frozen_string_literal: true

require 'open3'
require 'hue/sdk/entertainment'

RSpec.describe Hue::Sdk::Entertainment do
  let(:without_ffi) do
    <<~RUBY
      module Kernel
        alias_method :original_require, :require
        def require(name) = name == 'ffi' ? raise(LoadError, name) : original_require(name)
      end
      begin
        require 'hue/sdk/entertainment'
      rescue Hue::Sdk::Error => e
        print e.message
      end
    RUBY
  end

  it 'asks for the ffi gem when it is missing' do
    output, = Open3.capture2e(RbConfig.ruby, '-Ilib', '-e', without_ffi)
    expect(output).to include("add gem 'ffi' to your Gemfile")
  end
end
