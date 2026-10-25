# frozen_string_literal: true

require 'resolv'

RSpec.describe Miele::Sdk::Discovery do
  let(:dns) { Resolv::DNS }
  let(:appliance) do
    described_class::Appliance.new(name: 'Miele H7164BP', host: '192.0.2.20', port: 80, device_type: 13,
                                   group_id: '0123456789ABCDEF', connection: 1, pairing: false)
  end

  def answer(service: '_mieleathome._tcp.local', instance: 'Miele H7164BP')
    full = "#{instance}.#{service}."
    message = dns::Message.new(0)
    message.add_answer("#{service}.", 10, dns::Resource::IN::PTR.new(dns::Name.create(full)))
    additional(full).each { |name, data| message.add_additional(name, 10, data) }
    message.encode
  end

  def additional(instance)
    [
      [instance, dns::Resource::IN::SRV.new(0, 0, 80, dns::Name.create('Miele-001D63FFFE000001.local.'))],
      [instance, dns::Resource::IN::TXT.new('txtvers=1', 'group=0123456789ABCDEF', 'path=/', 'security=1',
                                            'pairing=false', 'devicetype=13', 'con=1', 'subtype=0', 's=0')],
      ['Miele-001D63FFFE000001.local.', dns::Resource::IN::A.new('192.0.2.20')]
    ]
  end

  it 'extracts an appliance from an mDNS response' do
    expect(described_class.parse(answer)).to eq([appliance])
  end

  it 'ignores answers for other services' do
    expect(described_class.parse(answer(service: '_hue._tcp.local'))).to eq([])
  end

  def flushed(type, data) = dns::Resource::Generic.create(type, 0x8001).new(data)

  def flushed_records(instance)
    host = "\x16Miele-001D63FFFE000001\x05local\x00".b
    txt = %w[group=0123456789ABCDEF pairing=false devicetype=13 con=1].map { [it.bytesize].pack('C') + it }.join
    [[instance, flushed(33, [0, 0, 80].pack('nnn') + host)], [instance, flushed(16, txt)],
     ['Miele-001D63FFFE000001.local.', flushed(1, [192, 0, 2, 20].pack('C4'))]]
  end

  it 'decodes records that carry the mDNS cache-flush bit' do
    instance = 'Miele H7164BP._mieleathome._tcp.local.'
    message = dns::Message.new(0)
    message.add_answer('_mieleathome._tcp.local.', 10, dns::Resource::IN::PTR.new(dns::Name.create(instance)))
    flushed_records(instance).each { |name, record| message.add_additional(name, 10, record) }
    expect(described_class.parse(message.encode)).to eq([appliance])
  end

  it 'ignores packets that are not DNS messages' do
    expect(described_class.parse('not a dns message')).to eq([])
  end

  it 'ignores a packet shorter than a DNS header' do
    expect(described_class.parse("\x00\x01")).to eq([])
  end

  it 'reads a TXT entry that has no value' do
    message = Resolv::DNS::Message.decode(answer)
    message.additional.map! do |name, ttl, data|
      [name, ttl, data.is_a?(dns::Resource::IN::TXT) ? dns::Resource::IN::TXT.new('flag', *data.strings) : data]
    end
    expect(described_class.parse(message.encode)).to eq([appliance])
  end

  context 'with a responder on the network' do
    let(:responder) { UDPSocket.new.tap { |socket| socket.bind('127.0.0.1', 0) } }
    let(:questions) { Queue.new }
    let(:lost_queries) { 0 }

    before do
      lost = lost_queries
      Thread.new do
        lost.times { responder.recvfrom(512) }
        query, from = responder.recvfrom(512)
        questions << dns::Message.decode(query).question.map { |name, type| [name.to_s, type] }
        2.times { responder.send(answer, 0, from[3], from[1]) }
      end
    end

    after { responder.close }

    it 'asks for Miele appliances and collects each one once', :aggregate_failures do
      found = described_class.discover(address: '127.0.0.1', port: responder.addr[1], timeout: 0.5, listen_port: 0)
      expect(found).to eq([appliance])
      expect(questions.pop).to eq([['_mieleathome._tcp.local', dns::Resource::IN::PTR]])
    end

    context 'when the first query is lost' do
      let(:lost_queries) { 1 }

      it 'asks again one second later' do
        expect(described_class.discover(address: '127.0.0.1', port: responder.addr[1], timeout: 1.5,
                                        listen_port: 0)).to eq([appliance])
      end
    end
  end
end
