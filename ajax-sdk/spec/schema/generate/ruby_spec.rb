# frozen_string_literal: true

require 'ajax/sdk/cloud/values'
require_relative '../../../schema/generate/ruby'

RSpec.describe Schema::Generate::Ruby do
  let(:klass) { ProbeSchema.message_class }
  let(:probe) { Ajax::Sdk::Cloud::Messages::Probe::Probe }
  let(:raw) do
    sample = { i: 2**40, s: 'x', state: :STATE_ON, states: %i[STATE_ON STATE_UNSPECIFIED], sub: { n: 1 },
               subs: [{ n: 2 }, {}], at: { seconds: 5, nanos: 7 }, d: { seconds: 1, nanos: 500_000_000 },
               w: { value: '' }, tags: { 'k' => { n: 4 } }, a: { n: 0 }, opt: 3 }
    klass.decode(klass.encode(klass.new(**sample))).to_h
  end

  before do
    stub_const('Ajax::Sdk::Cloud::Messages::Probe', Module.new)
    TOPLEVEL_BINDING.eval(described_class.file(ProbeSchema.model, 'probe.proto'))
  end

  it 'reads every kind of field from to_h', :aggregate_failures do
    value = probe.from(raw)
    expect(value).to have_attributes(i: 2**40, s: 'x', state: :on, states: %i[on unspecified], w: '', opt: 3, d: 1.5,
                                     at: Time.at(5, 7, :nsec, in: 'UTC'), choice: :a)
    expect([value.sub.n, value.subs.map(&:n), value.tags.transform_values(&:n), value.a.n])
      .to eq([1, [2, 0], { 'k' => 4 }, 0])
  end

  it 'gives absent fields their protobuf default' do
    expect(probe.from({})).to have_attributes(i: 0, s: '', state: :unspecified, states: [], sub: nil, subs: [], at: nil,
                                              d: nil, w: nil, tags: {}, a: nil, b: nil, opt: nil, choice: nil, raw: {})
  end

  it 'keeps an enum value it does not know as the integer' do
    expect(probe.from({ state: 7 }).state).to eq(7)
  end

  it 'writes back the message google-protobuf reads' do
    expect(klass.new(**probe.from(raw).to_message).to_h).to eq(raw)
  end

  it 'refuses an unknown keyword' do
    expect { probe.new(bogus: 1) }.to raise_error(ArgumentError, /bogus/)
  end
end
