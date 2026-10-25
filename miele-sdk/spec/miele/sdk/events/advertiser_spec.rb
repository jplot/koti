# frozen_string_literal: true

require 'resolv'

RSpec.describe Miele::Sdk::Events::Advertiser do
  subject(:advertiser) do
    described_class.new(fab: '000000004321', host: '192.0.2.50', port: 18_082, address: '127.0.0.1', mdns_port: 0)
  end

  let(:client) { UDPSocket.new.tap { it.bind('127.0.0.1', 0) } }

  before do
    Miele::Sdk.config.group_id = '0123456789ABCDEF'
    advertiser.start
  end

  after do
    advertiser.stop
    client.close
  end

  def ask(name, type)
    message = Resolv::DNS::Message.new(7)
    message.add_question(name, type)
    client.send(message.encode, 0, '127.0.0.1', advertiser.port)
    client.recvfrom(9000).first if client.wait_readable(1)
  end

  it 'answers an mDNS query for the advertised service' do
    expect(Miele::Sdk::Discovery.parse(ask('_mieleathome._tcp.local', Resolv::DNS::Resource::IN::PTR))).to eq(
      [Miele::Sdk::Discovery::Appliance.new(name: 'koti 000000004321', host: '192.0.2.50', port: 18_082,
                                            device_type: 2_147_483_647, group_id: '0123456789ABCDEF',
                                            connection: 2, pairing: false)]
    )
  end

  it 'answers a legacy unicast query with its id and question', :aggregate_failures do
    answer = Resolv::DNS::Message.decode(ask(advertiser.hostname, Resolv::DNS::Resource::IN::A))
    expect([answer.id, answer.question.map { it.first.to_s }]).to eq([7, [advertiser.hostname]])
    expect(answer.answer.map { it.last.address.to_s }).to eq(['192.0.2.50'])
  end

  it 'names its host after its fabrication number' do
    expect(advertiser.hostname).to eq('Miele-001D63FFFE0010E1.local')
  end

  it 'stays silent on queries for other names' do
    expect(ask('_hue._tcp.local', Resolv::DNS::Resource::IN::PTR)).to be_nil
  end
end
