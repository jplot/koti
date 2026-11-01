# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Exchange do
  subject(:exchange) { client.exchange(webrtc) }

  let(:client) { Ajax::Sdk::Cloud::Client.new(settings) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'local', grpc_port: 0, read_timeout: 0.2,
                                                        ca_file: nil, read_only: false, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:gateway) { FakeGateway.start({ webrtc => calls }) }

  before do
    allow(GRPC::ClientStub).to receive(:new).and_wrap_original do |original, *, **options|
      original.call("127.0.0.1:#{gateway.port}", :this_channel_is_insecure, **options)
    end
    allow(client.session).to receive_messages(ensure_login: nil, login: nil, metadata: {})
    gateway
  end

  after { gateway.stop }

  def webrtc = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_webrtc.StreamWebrtcService/execute'
  def init = { init: { video_edge_id: '0000ABCD' } }
  def answer = { answer: { session_description: { type: 'answer', sdp: 'v=0' } } }
  def offer = { success: { offer: { session_description: { type: 'offer', sdp: 'v=0' } } } }
  def sent = gateway.requests.map { |_path, request| request.compact.keys.first }

  context 'when the gateway ends the call while requests may still come' do
    let(:calls) { [[:read, offer]] }

    it 'returns after the last response' do
      expect { |probe| exchange.write(init).each(&probe) }
        .to yield_successive_args(have_attributes(signaling_message: :offer))
    end

    it 'leaves no thread behind' do
      threads = Thread.list
      exchange.write(init).each { nil }

      expect(Timeout.timeout(2) { sleep(0.05) until (Thread.list - threads).empty? }).to be_nil
    end
  end

  context 'when requests are written from another thread while responses flow' do
    let(:calls) { [[:read, offer, :read, offer]] }

    it 'sends them in order on the same call' do
      exchange.write(init).each { |message| Thread.new { exchange.write(answer) }.join if message.offer && sent.one? }

      expect(sent).to eq(%i[init answer])
    end
  end

  context 'when another thread closes the exchange' do
    let(:calls) { [%i[read open]] }

    it 'ends the call here and on the gateway', :aggregate_failures do
      Thread.new do
        sleep(0.05) until sent.any?
        exchange.close
      end

      expect(exchange.write(init).each { nil }).to be_nil
      expect(gateway.closed.pop(timeout: 1)).to eq(webrtc)
    end
  end

  context 'when another thread closes the exchange while it logs in' do
    let(:calls) { [%i[read open]] }

    it 'opens no call', :aggregate_failures do
      allow(client.session).to receive(:ensure_login) { exchange.close }

      expect(exchange.write(init).each { nil }).to be_nil
      expect(gateway.closed.pop(timeout: 0.5)).to be_nil
    end
  end

  context 'when the gateway cancels the call' do
    let(:calls) { [[:read, GRPC::Cancelled.new('gone')]] }

    it 'raises' do
      expect { exchange.write(init).each { nil } }.to raise_error(GRPC::Cancelled)
    end
  end

  context 'when the exchange is closed' do
    let(:calls) { [] }

    it 'refuses a write and a run', :aggregate_failures do
      exchange.close

      expect { exchange.write(init) }.to raise_error(IOError)
      expect { exchange.each { nil } }.to raise_error(IOError)
    end
  end

  context 'when a request does not fit the path' do
    let(:calls) { [] }

    it 'raises at the write, keeping nothing to send' do
      expect { exchange.write(bogus: 1) }.to raise_error(ArgumentError, /bogus/)
    end
  end

  context 'when the exchange already ran' do
    let(:calls) { [[:read, offer]] }

    it 'refuses another run' do
      exchange.write(init).each { nil }

      expect { exchange.each { nil } }.to raise_error(IOError)
    end
  end

  context 'when the exchange is running on another thread' do
    let(:calls) { [%i[read open]] }

    def quietly
      Thread.new do
        Thread.current.report_on_exception = false
        yield
      end
    end

    it 'refuses a second run' do
      running = Thread.new { exchange.write(init).each { nil } }
      sleep(0.05) until sent.any?

      expect { quietly { exchange.each { nil } }.join(2) }.to raise_error(IOError)
    ensure
      exchange.close
      running.join
    end
  end

  context 'without a block' do
    let(:calls) { [[:read, offer, :open]] }

    it 'reads the responses through an Enumerator, which closes the call when left', :aggregate_failures do
      expect(exchange.write(init).each.first.signaling_message).to eq(:offer)
      expect(gateway.closed.pop(timeout: 1)).to eq(webrtc)
    end
  end

  context 'when a response is a failure' do
    let(:calls) { [[:read, { failure: { permission_denied: {} } }, :open]] }

    it 'raises and closes the call on the gateway', :aggregate_failures do
      expect { exchange.write(init).each { nil } }.to raise_error(Ajax::Sdk::Cloud::ReadError, 'permission_denied')
      expect(gateway.closed.pop(timeout: 1)).to eq(webrtc)
    end

    it 'leaves no thread behind', :aggregate_failures do
      threads = Thread.list

      expect { exchange.write(init).each { nil } }.to raise_error(Ajax::Sdk::Cloud::ReadError)
      expect(Timeout.timeout(2) { sleep(0.05) until (Thread.list - threads).empty? }).to be_nil
    end
  end

  context 'when the session expires before the first response' do
    let(:calls) { [[:read, GRPC::Unauthenticated.new('expired')], [:read, :read, offer]] }

    it 'logs in again and replays what was written', :aggregate_failures do
      exchange.write(init).write(answer).each { nil }

      expect(client.session).to have_received(:login).once
      expect(sent).to eq(%i[init init answer])
    end
  end

  context 'when the client is read-only' do
    let(:calls) { [] }

    it 'refuses a path that writes' do
      allow(settings).to receive(:read_only).and_return(true)
      arm = '/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/arm'

      expect { client.exchange(arm) }.to raise_error(Ajax::Sdk::Cloud::ReadOnlyError)
    end
  end
end
