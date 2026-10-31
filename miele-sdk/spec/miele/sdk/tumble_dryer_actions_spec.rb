# frozen_string_literal: true

RSpec.describe Miele::Sdk::TumbleDryer do
  subject(:dryer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 2, 'ProtocolVersion' => 2) }
  let(:answers) { { 'DOP' => '{"Response":"86021201"}' } }
  let(:fake) do
    served = answers
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'POST', path: %r{/DOP/\z} } then [200, {}, served.fetch('DOP')]
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def dop1_requests = fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body).fetch('Request') }

  it "writes a Dop1 dryer's program on 8602, its structure version left at 0" do
    dryer.select_program(28)
    expect(dop1_requests).to eq(["86020100001c00#{'00' * 16}"])
  end
end
