# frozen_string_literal: true

require 'ajax/sdk/cloud/values'

RSpec.describe Ajax::Sdk::Cloud::Encode do
  let(:decode) { Ajax::Sdk::Cloud::Decode }

  it 'writes a time back as the Timestamp it was read from' do
    expect(described_class.time(decode.time({ seconds: 5, nanos: 7 }))).to eq({ seconds: 5, nanos: 7 })
  end

  it 'writes a duration back as the Duration it was read from', :aggregate_failures do
    expect(described_class.duration(decode.duration({ seconds: 1, nanos: 500_000_000 })))
      .to eq({ seconds: 1, nanos: 500_000_000 })
    expect(described_class.duration(-1.5)).to eq({ seconds: -1, nanos: -500_000_000 })
  end

  it 'refuses a time or a duration of another type', :aggregate_failures do
    expect { described_class.time(5) }.to raise_error(TypeError, /Time/)
    expect { described_class.duration('1') }.to raise_error(TypeError, /Numeric/)
  end

  it 'writes the content of a wrapper back', :aggregate_failures do
    expect(described_class.wrapper(decode.wrapper({ value: 'x' }, ''))).to eq({ value: 'x' })
    expect(decode.wrapper({}, '')).to eq('')
  end
end
