# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::LiveView do
  include_context 'with the Hue cloud'

  let(:passphrase) { 'alpha bravo charlie delta echo' }
  let(:camera) { FakeCamera.new(passphrase, 'cam-1') }
  let(:opened) { [] }

  after { opened.each(&:close) }

  def credentials = { AccessKeyId: 'AKIA-TEST', SecretAccessKey: 'secret-1', SessionToken: 'session-1' }

  def configuration(endpoint, camera_id)
    turn = { username: 'user-1', password: 'pass-1', urls: ['turn:t.example:443'], expires_at: '2026-11-14T21:00:00Z' }
    { credentials:, signaling_channels: [{ id: camera_id, arn: 'arn:aws:kinesisvideo:eu-west-1:1:channel/cam/1' }],
      turn_servers: [{ device_id: camera_id, ice_servers: [turn], http_signal_channel_endpoint: 'https://h.example',
                       wss_signal_channel_endpoint: endpoint }],
      stun_servers: ['stun:s.example:443'], earliest_expiry: '2026-11-14T20:00:00Z' }
  end

  def live(signaling, camera_id: 'cam-1')
    answer([{ id: 'key-1', public_key: camera.home_signing_pem, key_type: 'home_signing_public_key',
              upload_date: '2026-11-01T00:00:00Z' }])
    media = home.media(passphrase)
    answer([{ reported: { id: 'cam-1' } }, { reported: { id: 'cam-2' } }])
    answer(configuration(signaling.url, camera_id))
    media.live_view('cam-1').tap { opened << it }
  end

  def signaling(refuse: nil, &) = FakeSignaling.start(refuse:, &).tap { opened << it }

  def on_open = signaling { |message, peer| yield peer if message == :open }

  def payload(message) = JSON.parse(Base64.strict_decode64(message['messagePayload']))

  def candidate(number) = { candidate: "candidate:#{number}", sdp_mid: '0', sdp_mline_index: 0 }

  def send_candidate(view, number)
    view.candidate(candidate(number)[:candidate], **candidate(number).except(:candidate))
  end

  def presigned
    described_class.presign('wss://v-1.kinesisvideo.eu-west-1.amazonaws.com',
                            channel_arn: 'arn:channel', client_id: 'hue-sdk_1', time: Time.utc(2026, 11, 13, 10),
                            credentials: Hue::Sdk::Secure::Schema::SignalingServerCredentials.new(**credentials))
  end

  def answering(peer)
    peer.say('SDP_ANSWER', type: 'answer', sdp: 'v=0 answer', hueSignature: camera.sign('v=0 answer'))
    peer.say('ICE_CANDIDATE', candidate: 'candidate:1', sdpMid: '0', sdpMLineIndex: 0)
    peer.say('GO_AWAY', {})
  end

  it 'presigns the signaling URL as the app does', :aggregate_failures do
    url = presigned
    params = URI.decode_www_form(URI(url).query).to_h
    expect(params['X-Amz-Signature']).to eq(AppSigv4.signature(url, secret: 'secret-1'))
    expect(params).to include('X-Amz-Expires' => '299', 'X-Amz-Security-Token' => 'session-1',
                              'X-Amz-ChannelARN' => 'arn:channel', 'X-Amz-ClientId' => 'hue-sdk_1',
                              'X-Amz-Credential' => 'AKIA-TEST/20261113/eu-west-1/kinesisvideo/aws4_request')
  end

  it 'asks the cloud for the signaling credentials of every camera of the home' do
    live(signaling)
    expect(sent.values_at(0, 1, 3))
      .to eq(['POST', '/security/vss/v1/home/home-1/credentials/live-stream?turn_servers=true',
              '{"device_id_list":["cam-1","cam-2"]}'])
  end

  it 'gives the browser its ICE servers, STUN first, and when the credentials expire' do
    view = live(signaling)
    turn = { urls: ['turn:t.example:443'], username: 'user-1', credential: 'pass-1' }
    expect([view.ice_servers, view.earliest_expiry])
      .to eq([[{ urls: ['stun:s.example:443'] }, turn], '2026-11-14T20:00:00Z'])
  end

  it "opens the camera's channel with a client id of its own" do
    live(fake = signaling)
    expect(fake.query).to include('X-Amz-ChannelARN' => 'arn:aws:kinesisvideo:eu-west-1:1:channel/cam/1',
                                  'X-Amz-ClientId' => match(/\Ahue-sdk_\h{8}-\h{4}-/))
  end

  it 'sends an offer signed with the app key, as the app does', :aggregate_failures do
    live(fake = signaling).offer('v=0 offer')
    message = fake.wait_for(1).first
    client_id = fake.query['X-Amz-ClientId']
    expect(message).to include('action' => 'SDP_OFFER', 'senderClientId' => client_id)
    expect(payload(message)).to include('type' => 'offer', 'sdp' => 'v=0 offer', 'hueSender' => client_id,
                                        'hueHomeSigningPublicKeyUuid' => 'key-1')
    expect(camera.verify_app('v=0 offer', payload(message)['hueSignature'])).to be(true)
  end

  it "yields the camera's answer, its candidates and the other messages, in their order" do
    view = live(on_open { answering(it) })
    go_away = described_class::Message.new(type: 'GO_AWAY',
                                           message: { 'messageType' => 'GO_AWAY', 'messagePayload' => 'e30=' })
    expect(view.first(3)).to eq([described_class::Answer.new(sdp: 'v=0 answer'),
                                 described_class::Candidate.new(**candidate(1)), go_away])
  end

  it 'raises E2eeError on an answer the camera did not sign' do
    forged = FakeCamera.new(passphrase, 'cam-2').sign('v=0 answer')
    view = live(on_open { it.say('SDP_ANSWER', type: 'answer', sdp: 'v=0 answer', hueSignature: forged) })
    expect { view.first }.to raise_error(Hue::Sdk::Secure::E2eeError, /signature/)
  end

  it "answers the camera's offer to ConsumerViewer, signed", :aggregate_failures do
    offer = { type: 'offer', sdp: 'v=0 cam', hueSignature: camera.sign('v=0 cam') }
    view = live(fake = on_open { it.say('SDP_OFFER', **offer) })
    expect(view.first).to eq(described_class::Offer.new(sdp: 'v=0 cam'))
    view.answer('v=0 browser')
    message = fake.wait_for(1).first
    expect(message).to include('action' => 'SDP_ANSWER', 'recipientClientId' => 'ConsumerViewer')
    expect(camera.verify_app('v=0 browser', payload(message)['hueSignature'])).to be(true)
  end

  it 'drops a candidate without one, as the app does' do
    view = live(fake = signaling)
    view.candidate(nil, sdp_mid: '0', sdp_mline_index: 0)
    send_candidate(view, 2)
    expect(fake.wait_for(1).map { payload(it) })
      .to eq([{ 'candidate' => 'candidate:2', 'sdpMid' => '0', 'sdpMLineIndex' => 0 }])
  end

  it 'returns from each once the caller closes it from another thread' do
    view = live(signaling)
    reader = Thread.new { view.each { nil } }
    Thread.pass while reader.status == 'run'
    view.close
    expect(reader.join(5)).to be(reader)
  end

  it 'raises ConnectionError when Kinesis Video drops the connection, or closes the channel', :aggregate_failures do
    expect { live(on_open(&:drop)).each { nil } }.to raise_error(Hue::Sdk::ConnectionError)
    expect { live(on_open(&:hang_up)).each { nil } }.to raise_error(Hue::Sdk::ConnectionError, /closed/)
  end

  it 'raises ConnectionError on a send once the channel is closed, or the connection dropped', :aggregate_failures do
    view = live(signaling)
    view.close
    expect { view.offer('v=0') }.to raise_error(Hue::Sdk::ConnectionError)
    dropped = live(on_open(&:drop))
    expect { 100.times { dropped.offer('v=0').then { sleep 0.01 } } }.to raise_error(Hue::Sdk::ConnectionError)
  end

  # 40 kB each: a write then waits on a full socket buffer, and OpenSSL lets another thread's write in (5 runs out
  # of 5 without the lock).
  it 'keeps every frame whole while 4 threads send 50 candidates each during each' do
    view = live(fake = signaling)
    reader = Thread.new { view.each { nil } }
    sent = Array.new(200) { "candidate:#{it}:#{'x' * 40_000}" }
    sent.each_slice(50).map { |part| Thread.new { part.each { view.candidate(it, sdp_mid: '0', sdp_mline_index: 0) } } }
        .each(&:join)
    expect(fake.wait_for(200).map { payload(it)['candidate'] }.sort).to eq(sent.sort)
    reader.kill
  end

  it 'refuses a camera the cloud gives no channel for' do
    expect { live(signaling, camera_id: 'cam-2') }
      .to raise_error(Hue::Sdk::ResponseError, %r{Could not find signaling channel / turn server config})
  end

  it 'raises ResponseError, with its status, when Kinesis Video refuses the signed URL', :aggregate_failures do
    expect { live(signaling(refuse: 403)) }.to raise_error(Hue::Sdk::ResponseError) { expect(it.status).to eq(403) }
  end

  it 'asks for the websocket-driver gem when it is missing' do
    allow(Hue::Sdk::Secure::Media).to receive(:require).with('websocket/driver').and_raise(LoadError)
    expect { live(signaling) }.to raise_error(Hue::Sdk::Error, /gem 'websocket-driver'/)
  end
end
