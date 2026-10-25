# frozen_string_literal: true

require 'resolv'

RSpec.describe Hue::Sdk::Discovery do
  let(:dns) { Resolv::DNS }
  let(:bridge) do
    described_class::Bridge.new(name: 'Hue Bridge - 000001', host: '192.0.2.10', port: 443,
                                bridge_id: 'ECB5FAFFFE000001', model_id: 'BSB003')
  end

  def answer(service: '_hue._tcp.local', instance: 'Hue Bridge - 000001')
    full = "#{instance}.#{service}."
    message = dns::Message.new(0)
    message.add_answer("#{service}.", 10, dns::Resource::IN::PTR.new(dns::Name.create(full)))
    additional(full).each { |name, data| message.add_additional(name, 10, data) }
    message.encode
  end

  def additional(instance)
    [
      [instance, dns::Resource::IN::SRV.new(0, 0, 443, dns::Name.create('ECB5FA000001.local.'))],
      [instance, dns::Resource::IN::TXT.new('bridgeid=ecb5fafffe000001', 'modelid=BSB003')],
      ['ECB5FA000001.local.', dns::Resource::IN::A.new('192.0.2.10')]
    ]
  end

  it 'extracts a bridge from an mDNS response' do
    expect(described_class.parse(answer)).to eq([bridge])
  end

  it 'ignores answers for other services' do
    expect(described_class.parse(answer(service: '_mieleathome._tcp.local'))).to eq([])
  end

  it 'ignores packets that are not DNS messages' do
    expect(described_class.parse('not a dns message')).to eq([])
  end

  context 'with a responder on the network' do
    let(:responder) { UDPSocket.new.tap { |socket| socket.bind('127.0.0.1', 0) } }
    let(:questions) { Queue.new }

    before do
      Thread.new do
        query, from = responder.recvfrom(512)
        questions << dns::Message.decode(query).question.map { |name, type| [name.to_s, type] }
        2.times { responder.send(answer, 0, from[3], from[1]) }
      end
    end

    after { responder.close }

    it 'asks for Hue bridges and collects each answering bridge once', :aggregate_failures do
      found = Hue::Sdk.discover(address: '127.0.0.1', port: responder.addr[1], timeout: 0.5)
      expect(found).to eq([bridge])
      expect(questions.pop).to eq([['_hue._tcp.local', dns::Resource::IN::PTR]])
    end
  end

  it 'returns an empty list when nobody answers' do
    silent = UDPSocket.new.tap { |socket| socket.bind('127.0.0.1', 0) }
    expect(Hue::Sdk.discover(address: '127.0.0.1', port: silent.addr[1], timeout: 0.2)).to eq([])
  ensure
    silent&.close
  end
end
