# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Media do
  include_context 'with the Hue cloud'

  let(:passphrase) { 'alpha bravo charlie delta echo' }
  let(:camera) { FakeCamera.new(passphrase, 'cam-1') }
  let(:cek) { Random.bytes(16) }

  def error = Hue::Sdk::Secure::E2eeError

  def snapshots = '/security/event-service/v1/home/home-1/device/cam-1/timestamp'

  def published(*keys)
    answer(keys.map.with_index(1) do |(pem, date), index|
      { id: "key-#{index}", public_key: pem, key_type: 'home_signing_public_key', upload_date: date }
    end)
  end

  def other = FakeCamera.new('foxtrot golf hotel india juliett', 'cam-1').home_signing_pem

  def opened
    published([camera.home_signing_pem, '2026-11-01T00:00:00Z'])
    home.media(passphrase)
  end

  def snapshot_answer(**extra) = answer(snapshot: Base64.strict_encode64(camera.snapshot_blob('jpeg', cek)), **extra)

  describe 'opening the media of a home' do
    it 'checks the passphrase against the newest home signing key, and keeps its id', :aggregate_failures do
      published([camera.home_signing_pem, '2026-11-02T00:00:00Z'], [other, '2026-10-01T00:00:00Z'])
      expect(home.media(passphrase).signing_key_id).to eq('key-1')
      expect(cloud.requests.last.path)
        .to eq('/security/E2EE-public-keys-service/v1/home/home-1/e2ee/public-key?key_type=home_signing_public_key')
    end

    it 'calls an older passphrase old' do
      published([camera.home_signing_pem, '2026-10-01T00:00:00Z'], [other, '2026-11-02T00:00:00Z'])
      expect { home.media(passphrase) }.to raise_error(error, /old one/)
    end

    it 'calls a passphrase wrong when no key matches, or there is none', :aggregate_failures do
      published([other, '2026-11-02T00:00:00Z'])
      expect { home.media(passphrase) }.to raise_error(error, satisfy { it.include?('wrong') && !it.include?('alpha') })
      published
      expect { home.media(passphrase) }.to raise_error(error, /wrong/)
    end

    it 'calls a passphrase with a trailing space wrong, as the app does' do
      published([camera.home_signing_pem, '2026-11-02T00:00:00Z'])
      expect { home.media("#{passphrase} ") }.to raise_error(error, /wrong/)
    end
  end

  describe 'snapshots' do
    it 'decrypts the latest snapshot of a camera', :aggregate_failures do
      media = opened
      snapshot_answer(timestamp: '2026-11-13T10:00:00Z', refresh_timestamp: '2026-11-13T10:00:05Z')
      expect(media.snapshot('cam-1')).to eq(described_class::Snapshot.new(
                                              image: 'jpeg', timestamp: '2026-11-13T10:00:00Z',
                                              refresh_timestamp: '2026-11-13T10:00:05Z'
                                            ))
      expect(sent.first(2)).to eq(['GET', "#{snapshots}/latest/snapshot"])
    end

    it 'reads the snapshot of an event at its device time', :aggregate_failures do
      media = opened
      snapshot_answer(timestamp: '2026-11-13T10:00:00Z')
      expect(media.snapshot('cam-1', at: Time.at(1_763_000_000)).image).to eq('jpeg')
      expect(cloud.requests.last.path).to eq("#{snapshots}/1763000000/snapshot")
    end

    it 'decrypts the snapshot behind a snapshot_url, sending no token', :aggregate_failures do
      media = opened
      answers.push([200, { 'Content-Type' => 'application/octet-stream' }, camera.snapshot_blob('jpeg', cek)])
      expect(media.snapshot_at('cam-1', "#{cloud.url}/snapshots/1")).to eq('jpeg')
      expect(cloud.requests.last.headers).not_to include('authorization')
    end

    it 'raises ResponseError, not a token error, when a snapshot_url has expired', :aggregate_failures do
      media = opened
      answers.push([403, { 'Content-Type' => 'application/xml' }, '<Error><Code>AccessDenied</Code></Error>'])
      expect { media.snapshot_at('cam-1', "#{cloud.url}/snapshots/1") }
        .to raise_error(Hue::Sdk::ResponseError) { expect(it.status).to eq(403) }
    end

    it 'calls a passphrase with a capital letter wrong, as the app does' do
      published([camera.home_signing_pem, '2026-11-02T00:00:00Z'])
      expect { home.media(passphrase.capitalize) }.to raise_error(error, /wrong/)
    end

    it 'refuses a snapshot whose image does not decrypt' do
      media = opened
      blob = camera.snapshot_blob('jpeg', cek).tap { it.setbyte(250, it.getbyte(250) ^ 1) }
      answer(snapshot: Base64.strict_encode64(blob), timestamp: '2026-11-13T10:00:00Z')
      expect { media.snapshot('cam-1') }.to raise_error(error)
    end
  end

  describe 'clips' do
    let(:files) do
      { '/hls/master.m3u8' => "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nclip.m3u8\n",
        '/hls/clip.m3u8' => fixture('clip.m3u8'), '/hls/init.mp4' => init,
        '/hls/segment1.m4s' => camera.seal_segment(segment, cek:) }
    end
    let(:upstream) { FakeCloud.start { |request| [200, {}, files.fetch(request.path.split('?').first)] } }

    after { upstream.stop }

    def fixture(name) = File.binread(File.expand_path("../../../fixtures/media/#{name}", __dir__))

    def init = fixture('init.mp4')

    def segment = fixture('segment1.m4s')

    def clip(playlist = 'clip.m3u8')
      media = opened
      answer(data: { url: "#{upstream.url}/hls/#{playlist}?t=1", expiration: 300,
                     keyEnvelope: Base64.strict_encode64(camera.envelope(cek)) })
      media.clip('cam-1', 'clip-9')
    end

    it 'asks the event service for the clip' do
      clip
      expect(cloud.requests.last.path).to eq('/security/event-service/v1/home/home-1/device/cam-1/clip/clip-9')
    end

    it 'refuses a clip the event service gives no playlist for' do
      media = opened
      answer(data: { url: nil, expiration: 300, keyEnvelope: Base64.strict_encode64(camera.envelope(cek)) })
      expect { media.clip('cam-1', 'clip-9') }.to raise_error(Hue::Sdk::ResponseError, /no playlist or key/)
    end

    it 'gives its playlist and init as they are, and its segments decrypted', :aggregate_failures do
      read = clip
      expect([read.entry, read.expiration]).to eq(['/hls/clip.m3u8?t=1', 300])
      expect(read.get('clip.m3u8?t=1').body).to eq(files['/hls/clip.m3u8'])
      expect(read.get('init.mp4').body).to eq(init)
      expect(SegmentReader.samples(read.get('segment1.m4s').body, init:)).to eq(SegmentReader.samples(segment, init:))
    end

    it 'keeps the sync flags the boxes give, even where sealed data looks like a key frame' do
      files['/hls/segment1.m4s'] = camera.seal_segment(segment, cek:, nonce: "\x00\x00\x00\x01\x65#{"\x00" * 7}".b)
      expect(SegmentReader.samples(clip.get('segment1.m4s').body, init:)).to eq(SegmentReader.samples(segment, init:))
    end

    it 'finds the initialization segment through a master playlist' do
      read = clip('master.m3u8')
      expect(SegmentReader.samples(read.get('segment1.m4s').body, init:)).to eq(SegmentReader.samples(segment, init:))
    end

    it 'finds the initialization segment of the video variant, past the renditions listed before it' do
      files['/hls/master.m3u8'] = <<~M3U8
        #EXTM3U
        #EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",NAME="cc",INSTREAM-ID="CC1"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="a",URI="audio.m3u8"
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=10,URI="iframe.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1000
        clip.m3u8
      M3U8
      expect(SegmentReader.samples(clip('master.m3u8').get('segment1.m4s').body, init:))
        .to eq(SegmentReader.samples(segment, init:))
    end

    it 'refuses a path of another origin' do
      expect { clip.get('//evil.test/x') }.to raise_error(ArgumentError)
    end

    it 'shows not its content key, nor does its proxy' do
      read = clip
      expect(read.inspect + Hue::Sdk::Secure::ClipProxy.new(read).inspect).not_to include(cek.inspect[1...-1])
    end
  end

  describe 'clip downloads' do
    before { Hue::Sdk::Secure.configure { it.kinesis_url = cloud.url } }

    def clip = File.binread(File.expand_path('../../../fixtures/media/clip.mp4', __dir__))

    def credentials
      answer(credential: { accessKeyId: 'AKIA-TEST', secretAccessKey: 'secret-1', sessionToken: 'session-1' },
             clip_metadata: { fragment_selector_type: 'SERVER_TIMESTAMP', start_timestamp: '2026-11-13T10:00:00.750Z',
                              end_timestamp: '2026-11-13T10:00:30.250Z', stream_name: 'stream-1',
                              key_envelope: Base64.strict_encode64(camera.envelope(cek)) })
    end

    def kinesis(sealed)
      answers.push(FakeCloud.json(DataEndpoint: cloud.url), [200, { 'Content-Type' => 'video/mp4' }, sealed])
    end

    def downloaded(sealed = camera.seal_mp4(clip, cek:))
      media = opened
      credentials
      kinesis(sealed)
      media.download_clip('cam-1', 'clip-9')
    end

    it 'asks the cloud for credentials, then Kinesis Video for the clip, and gives it in clear', :aggregate_failures do
      expect(SegmentReader.file_samples(downloaded)).to eq(SegmentReader.file_samples(clip))
      expect(cloud.requests.map { [it.verb, it.path] }.last(3))
        .to eq([%w[POST /security/vss/v1/home/home-1/clip/clip-9/credentials/download], %w[POST /getDataEndpoint],
                %w[POST /getClip]])
    end

    it 'asks Kinesis Video for the stream, then for the clip in whole seconds, as the app does' do
      downloaded
      range = { 'StartTimestamp' => 1_794_564_000, 'EndTimestamp' => 1_794_564_030 }
      selector = { 'FragmentSelectorType' => 'SERVER_TIMESTAMP', 'TimestampRange' => range }
      expect(cloud.requests.last(2).map { JSON.parse(it.body) })
        .to eq([{ 'StreamName' => 'stream-1', 'APIName' => 'GET_CLIP' },
                { 'StreamName' => 'stream-1', 'ClipFragmentSelector' => selector }])
    end

    it 'signs both requests to Kinesis Video with the clip credentials, in eu-west-1' do
      downloaded
      signed = start_with('AWS4-HMAC-SHA256 Credential=AKIA-TEST/').and(include('/eu-west-1/kinesisvideo/aws4_request'))
      expect(cloud.requests.last(2).map { it.headers.values_at('authorization', 'x-amz-security-token') })
        .to all(match([signed, 'session-1']))
    end

    it "reaches Kinesis Video in the region's own host unless told otherwise, eu-west-1 by default" do
      config = Hue::Sdk::Secure.config
      config.kinesis_url = nil
      urls = [config.kinesis_url, config.tap { it.kinesis_region = 'us-east-1' }.kinesis_url]
      expect(urls).to eq(%w[https://kinesisvideo.eu-west-1.amazonaws.com https://kinesisvideo.us-east-1.amazonaws.com])
    end

    it 'refuses a clip whose samples do not decrypt' do
      expect { downloaded(camera.seal_mp4(clip, cek: Random.bytes(16))) }.to raise_error(error)
    end

    it 'refuses a download the cloud gives no credentials for' do
      media = opened
      answer({})
      expect { media.download_clip('cam-1', 'clip-9') }.to raise_error(Hue::Sdk::ResponseError, /no credentials/)
    end

    it 'raises ResponseError, with its status, when Kinesis Video refuses the credentials', :aggregate_failures do
      media = opened
      credentials
      answers.push([403, { 'X-Amzn-ErrorType' => 'NotAuthorizedException' }, '{"message":"The token has expired"}'])
      expect { media.download_clip('cam-1', 'clip-9') }
        .to raise_error(Hue::Sdk::ResponseError, /expired/) { expect(it.status).to eq(403) }
    end

    it 'asks Kinesis Video once, as the app does, even when it fails', :aggregate_failures do
      media = opened
      credentials
      answers.push([500, { 'X-Amzn-ErrorType' => 'InternalFailure' }, '{"message":"down"}'])
      expect { media.download_clip('cam-1', 'clip-9') }.to raise_error(Hue::Sdk::ResponseError)
      expect(cloud.requests.count { it.path == '/getDataEndpoint' }).to eq(1)
    end

    it 'gives up on Kinesis Video after the read timeout set' do
      slow = FakeCloud.start { sleep(1).then { [404, {}, ''] } }
      Hue::Sdk::Secure.configure { it.kinesis_url = slow.url }
      media = opened
      credentials
      Hue::Sdk::Secure.configure { it.read_timeout = 0.2 }
      expect { media.download_clip('cam-1', 'clip-9') }.to raise_error(Hue::Sdk::ConnectionError)
    ensure
      slow&.stop
    end

    it 'raises ConnectionError when Kinesis Video cannot be reached' do
      media = opened
      credentials
      Hue::Sdk::Secure.configure { it.kinesis_url = 'http://127.0.0.1:1' }
      expect { media.download_clip('cam-1', 'clip-9') }.to raise_error(Hue::Sdk::ConnectionError)
    end

    it 'asks for the aws gems when they are missing' do
      media = opened
      credentials
      allow(described_class).to receive(:require).with('aws-sdk-kinesisvideo').and_raise(LoadError)
      expect { media.download_clip('cam-1', 'clip-9') }.to raise_error(Hue::Sdk::Error, /gem 'aws-sdk-kinesisvideo'/)
    end
  end
end
