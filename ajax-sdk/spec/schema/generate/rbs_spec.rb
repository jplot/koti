# frozen_string_literal: true

require 'rbs'
require_relative '../../../schema/generate/rbs'

RSpec.describe Schema::Generate::Rbs do
  subject(:source) { described_class.file(ProbeSchema.model, 'probe.proto') }

  it 'writes signatures RBS parses' do
    expect { RBS::Parser.parse_signature(source) }.not_to raise_error
  end

  it 'types an enum field as its symbols or an integer', :aggregate_failures do
    expect(source).to include('attr_reader state: ::Ajax::Sdk::Cloud::Messages::Probe::State::value | ::Integer')
    expect(source).to include('type value = :unspecified | :on')
  end
end
