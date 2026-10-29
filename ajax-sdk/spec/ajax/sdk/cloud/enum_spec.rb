# frozen_string_literal: true

require 'ajax/sdk/cloud/values'

RSpec.describe Ajax::Sdk::Cloud::Enum do
  subject(:state) do
    Module.new.tap do |state|
      state.extend(described_class)
      state.const_set(:VALUES, { STATE_UNSPECIFIED: :unspecified, STATE_ON: :on }.freeze)
    end
  end

  it 'reads a protobuf name, a number it does not know, or nothing' do
    expect([state.from(:STATE_ON), state.from(7), state.from(nil)]).to eq([:on, 7, :unspecified])
  end

  it 'writes a short symbol or a number back' do
    expect([state.proto(:on), state.proto(7)]).to eq([:STATE_ON, 7])
  end

  it 'refuses a symbol the enum does not have' do
    expect { state.proto(:nope) }.to raise_error(ArgumentError, /nope/)
  end
end
