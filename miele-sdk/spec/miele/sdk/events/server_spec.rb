# frozen_string_literal: true

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

  def send_to_server(*, **) = deliver(server.port, *, **)

  def supervision(peer) = "/Devices/000000004321/SuperVision/#{peer}/State/"

  it 'emits a pushed state change', :aggregate_failures do
    expect(send_to_server('POST', supervision('000111222333'), push).code).to eq('204')
    event = Miele::Sdk::Events::Event.new(fab: '000111222333', resource: '/State/', content: { 'Status' => 5 })
    expect(events.pop(timeout: 1)).to eq(event)
  end

  it 'drops a push whose signature is wrong and says so', :aggregate_failures do
    expect { send_to_server('POST', supervision('000111222333'), push, group_key: 'AB' * 64) }
      .to output(/refused a request from 127\.0\.0\.1 \(Host: 127\.0\.0\.1\)/).to_stderr
    expect(events.pop(timeout: 0.2)).to be_nil
  end

  it 'accepts a subscription with 201 and a Location', :aggregate_failures do
    response = send_to_server('POST', '/Subscriptions', JSON.generate(Resource: '/Devices/000000004321/State/'))
    expect(response.code).to eq('201')
    expect(response['Location']).to match(%r{\Ahttp://127\.0\.0\.1/Subscriptions/\d+/\z})
  end

  it 'gives a resource the same subscription slot each time' do
    body = JSON.generate(Resource: '/Ident/')
    locations = Array.new(2) { send_to_server('POST', '/Subscriptions', body)['Location'] }
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
    threads = peers.map { |peer| Thread.new { gate.pop && send_to_server('POST', supervision(peer), push) } }
    8.times { gate << true }
    threads.each(&:join)
    expect(Array.new(9) { events.pop(timeout: 0.5)&.fab }.compact.sort).to eq(peers)
  end
end
