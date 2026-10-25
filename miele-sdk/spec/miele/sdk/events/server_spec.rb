# frozen_string_literal: true

require 'net/http'

RSpec.describe Miele::Sdk::Events::Server do
  subject(:server) { described_class.new(port: 0, fab: '000000004321') { events << it } }

  let(:events) { Queue.new }
  let(:push) { JSON.generate(Resource: '/State/', Host: 'Miele-001D63FFFE000001.local', Content: { Status: 5 }) }

  before do
    Miele::Sdk.configure do |config|
      config.group_id = FakeAppliance::GROUP_ID
      config.group_key = FakeAppliance::GROUP_KEY
    end
    server.start
    Miele::Sdk.config.port = server.port
  end

  after { server.stop }

  def deliver(verb, path, body = '', group_key: FakeAppliance::GROUP_KEY)
    request = Net::HTTP.const_get(verb.capitalize).new(path)
    key = [group_key].pack('H*')
    Miele::Sdk::Connection.sign(request, '127.0.0.1', body.empty? ? '' : Miele::Sdk::Crypto.pad(body),
                                [FakeAppliance::GROUP_ID].pack('H*'), key)
    Net::HTTP.start('127.0.0.1', server.port) { it.request(request) }
  end

  def supervision(peer) = "/Devices/000000004321/SuperVision/#{peer}/State/"

  it 'emits a pushed state change', :aggregate_failures do
    expect(deliver('POST', supervision('000111222333'), push).code).to eq('204')
    event = Miele::Sdk::Events::Event.new(fab: '000111222333', resource: '/State/', content: { 'Status' => 5 })
    expect(events.pop(timeout: 1)).to eq(event)
  end

  it 'drops a push whose signature is wrong', :aggregate_failures do
    expect(deliver('POST', supervision('000111222333'), push, group_key: 'AB' * 64).code).to eq('403')
    expect(events.pop(timeout: 0.2)).to be_nil
  end

  it 'accepts a subscription with 201 and a Location', :aggregate_failures do
    response = deliver('POST', '/Subscriptions', JSON.generate(Resource: '/Devices/000000004321/State/'))
    expect(response.code).to eq('201')
    expect(response['Location']).to match(%r{\Ahttp://127\.0\.0\.1/Subscriptions/\d+/\z})
  end

  it 'gives a resource the same subscription slot each time' do
    locations = Array.new(2) { deliver('POST', '/Subscriptions', JSON.generate(Resource: '/Ident/'))['Location'] }
    expect(locations.uniq.size).to eq(1)
  end

  it 'answers identification requests with signed responses', :aggregate_failures do
    ident = JSON.parse(Miele::Sdk::Connection.request('127.0.0.1', :get, '/Devices/000000004321/Ident').body)
    expect(ident).to include('DeviceType' => 2_147_483_647, 'DeviceName' => 'koti')
    expect(JSON.parse(Miele::Sdk::Connection.request('127.0.0.1', :get, '/Devices/').body).keys)
      .to eq(['000000004321'])
  end

  it 'emits each of 8 simultaneous pushes once' do
    peers = Array.new(8) { format('0001112223%02d', it) }
    gate = Queue.new
    threads = peers.map { |peer| Thread.new { gate.pop && deliver('POST', supervision(peer), push) } }
    8.times { gate << true }
    threads.each(&:join)
    expect(Array.new(9) { events.pop(timeout: 0.5)&.fab }.compact.sort).to eq(peers)
  end
end
