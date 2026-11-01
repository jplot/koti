# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::LiveVideo do
  let(:client) { Ajax::Sdk::Cloud::Client.new(settings) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'local', grpc_port: 0, read_timeout: 0.2,
                                                        ca_file: nil, read_only: true, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:gateway) { FakeGateway.start({ webrtc => calls }) }

  before do
    allow(GRPC::ClientStub).to receive(:new).and_wrap_original do |original, *, **options|
      original.call("127.0.0.1:#{gateway.port}", :this_channel_is_insecure, **options)
    end
    allow(client.session).to receive_messages(ensure_login: {}, metadata: {})
  end

  after { gateway.stop }

  def webrtc = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_webrtc.StreamWebrtcService/execute'

  def channel
    Ajax::Sdk::Cloud::VideoChannel.new(space_id: 's1', video_edge_id: '0000ABCD', channel_id: 'ch-1', ptz: false,
                                       sub_stream: true, sound: true, raw: nil)
  end

  def view = Ajax::Sdk::Cloud::Streams::View.new(channel:, number: 1, quality: :main)

  def stream(tag = 0) = Ajax::Sdk::Cloud::Streams.live(view, tag:)

  def sent = gateway.requests.map { |_path, request| request.compact }

  def session = client.live_video('s1', '0000ABCD', [stream])

  def server = { urls: ['turn:turn.example.com'], username: 'u', credential: 'p' }

  def ice = { success: { init: { ice_servers: [server] } } }

  def offer = { success: { offer: { session_description: { sdp: 'v=0 offer' } } } }

  def answer = { success: { answer: { session_description: { sdp: 'v=0 answer' } } } }

  def candidate
    { success: { new_ice_candidate: { candidate: { sdp: 'candidate:0', sdp_mid: '0', sdp_mline_index: 1 } } } }
  end

  context 'when the far end offers' do
    let(:calls) { [[:read, ice, :read, offer, candidate, answer, :read, :read, :read, :read]] }

    def answering(live)
      live.answer('v=0 mine').candidate('candidate:1', sdp_mid: '0', sdp_mline_index: 1)
      live.established(latency: 0.25, candidate_type: :relay, network: :wifi).ask_streams([stream, stream(1)])
    end

    def relay(live)
      received = []
      live.each do |signal|
        received << signal
        answering(live) if signal[:type] == 'offer'
      end
      received
    end

    it 'gives the browser each signal, typed by the message that carries it' do
      expect(relay(session)).to eq(
        [{ iceServers: [server] }, { type: 'offer', sdp: 'v=0 offer' },
         { candidate: 'candidate:0', sdpMid: '0', sdpMLineIndex: 1 }, { type: 'answer', sdp: 'v=0 answer' }]
      )
    end

    it 'sends the streams again once the init came, then the browser signals', :aggregate_failures do
      relay(session)

      expect(sent.map { it.keys.first })
        .to eq(%i[init ask_streams answer new_ice_candidate peer_connection_established ask_streams])
      expect(sent.select { it[:ask_streams] }.map { it[:ask_streams][:streams].size }).to eq([1, 2])
    end

    it 'words each browser signal as the app does', :aggregate_failures do
      relay(session)

      expect(sent[2][:answer][:session_description]).to eq({ type: 'answer', sdp: 'v=0 mine' })
      expect(sent[3][:new_ice_candidate][:candidate]).to eq({ sdp: 'candidate:1', sdp_mid: '0', sdp_mline_index: 1 })
      expect(sent[4][:peer_connection_established]).to eq(
        latency: { nanos: 250_000_000 }, ice_candidate_type: :ICE_CANDIDATE_TYPE_RELAY,
        network_technology_type: :NETWORK_TECHNOLOGY_TYPE_WIFI
      )
    end
  end

  context 'when it opens' do
    let(:calls) { [[:read]] }

    it 'sends the init the app sends: every ICE candidate allowed, large RTP packets on' do
      session.each { nil }

      expect(sent.first[:init]).to include(
        space_locator: { space_id: 's1' }, video_edge_id: '0000ABCD', allow_large_rtp_packets: true,
        initial_streams: [include(id: '1-lm', channel_guid: 'ch-1')],
        ice_filters: include(type_filter: { host: true, reflexive: true, relay: true },
                             protocol_filter: { tcp: true, udp: true })
      )
    end

    it 'leaves large RTP packets off when asked' do
      client.live_video('s1', '0000ABCD', [stream], allow_large_rtp_packets: false).each { nil }

      expect(sent.first[:init].fetch(:allow_large_rtp_packets, false)).to be(false)
    end
  end

  context 'when the streams change before the init came' do
    let(:calls) { [[:read, ice, :read]] }

    it 'holds the list until then' do
      exchange = instance_double(Ajax::Sdk::Cloud::Exchange, write: nil)
      described_class.new(exchange, [stream]).ask_streams([stream, stream(1)])

      expect(exchange).not_to have_received(:write)
    end

    it 'sends the last list once, when the init comes', :aggregate_failures do
      session.ask_streams([stream, stream(1)]).each { nil }

      expect(sent.map { it.keys.first }).to eq(%i[init ask_streams])
      expect(sent.last[:ask_streams][:streams].size).to eq(2)
    end
  end

  context 'when the browser renegotiates, as it does to add its talk-back track' do
    let(:calls) { [%i[read read]] }

    it 'sends its offer' do
      session.offer('v=0 talk').each { nil }

      expect(sent.last).to eq({ offer: { session_description: { type: 'offer', sdp: 'v=0 talk' } } })
    end
  end

  context 'when the gateway answers the asked streams' do
    let(:calls) { [[:read, { success: { ask_streams_response: { success: {} } } }, offer]] }

    it 'leaves the answer out, as the app ignores it' do
      expect(session.each.to_a).to eq([{ type: 'offer', sdp: 'v=0 offer' }])
    end
  end

  context 'when the browser leaves' do
    let(:calls) { [%i[read open]] }

    it 'ends the session on the gateway', :aggregate_failures do
      live = session
      Thread.new do
        sleep(0.05) until sent.any?
        live.close
      end

      expect(live.each { nil }).to be_nil
      expect(gateway.closed.pop(timeout: 1)).to eq(webrtc)
    end
  end

  context 'when the camera is offline' do
    let(:calls) { [[:read, { failure: { video_edge_is_offline: {} } }]] }

    it 'raises the reason' do
      expect { session.each { nil } }.to raise_error(Ajax::Sdk::Cloud::ReadError, 'video_edge_is_offline')
    end
  end
end
