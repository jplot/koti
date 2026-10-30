# frozen_string_literal: true

require 'open3'
require 'rbs'
require 'ajax/sdk/cloud/values'
require_relative '../../../../schema/generate/model'

RSpec.describe Ajax::Sdk::Cloud::Messages do
  let(:root) { File.expand_path('../../../..', __dir__) }
  let(:model) { Schema::Generate::Model.load(File.join(root, 'lib/ajax/sdk/cloud/schemas')) }
  let(:arm) { 'systems.ajax.api.mobile.v2.space.security.ArmSpaceResponse' }
  let(:racing) do
    <<~RUBY
      require 'ajax/sdk/cloud/values'
      gate = Queue.new
      threads = Array.new(8) { Thread.new { gate.pop && Ajax::Sdk::Cloud::Messages.type('#{arm}') } }
      8.times { gate << true }
      print threads.map(&:value).uniq.size
    RUBY
  end

  def attributes(declaration, outer = nil)
    name = [outer, declaration.name.to_s].compact.join('::')
    nested = declaration.members.grep(RBS::AST::Declarations::Class).flat_map { attributes(it, name) }
    readers = declaration.members.grep(RBS::AST::Members::AttrReader).map(&:name)
    declaration.is_a?(RBS::AST::Declarations::Class) ? [[name, readers], *nested] : nested
  end

  it 'loads every generated message and builds it from an empty hash' do
    classes = model.messages.map { Object.const_get(it.constant) }
    expect(classes.reject { it.from({}).is_a?(it) }).to be_empty
  end

  it 'declares in RBS the members each class has' do
    signatures = Dir[File.join(root, 'sig/ajax/sdk/cloud/messages/**/*.rbs')]
    declared = signatures.flat_map { RBS::Parser.parse_signature(File.read(it)).last.flat_map { attributes(it) } }.to_h
    expect(declared).to eq(model.messages.to_h { [it.constant, Object.const_get(it.constant).members] })
  end

  it 'loads a class once when two threads reach it first' do
    expect(Open3.capture2e(RbConfig.ruby, '-Ilib', '-e', racing, chdir: root).then { [it.first, it.last.success?] })
      .to eq(['1', true])
  end

  it 'finds the response class of a method', :aggregate_failures do
    expect(described_class.type(arm)).to eq(Ajax::Sdk::Cloud::Messages::Api::Mobile::V2::Space::Security::ArmSpaceResponse)
    expect { described_class.type('p.Nope') }.to raise_error(Ajax::Sdk::Cloud::UnknownMessageError, /p.Nope/)
  end
end
