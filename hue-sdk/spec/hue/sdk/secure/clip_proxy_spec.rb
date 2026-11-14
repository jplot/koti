# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::ClipProxy do
  subject(:proxy) { described_class.new(Hue::Sdk::Secure::Clip.new(URI("#{upstream.url}/hls/clip.m3u8?t=1"), 300, cek)) }

  let(:cek) { Random.bytes(16) }
  let(:files) do
    camera = FakeCamera.new('alpha bravo charlie delta echo', 'cam-1')
    { '/hls/clip.m3u8' => [200, fixture('clip.m3u8')], '/hls/init.mp4' => [200, fixture('init.mp4')],
      '/hls/segment0.m4s' => [200, camera.seal_segment(fixture('segment0.m4s'), cek:)],
      '/hls/segment1.m4s' => [200, camera.seal_segment(fixture('segment1.m4s'), cek:)] }
  end
  let(:upstream) do
    FakeCloud.start(threaded: true) do |request|
      status, body, headers = files.fetch(request.path.split('?').first, [404, ''])
      [status, headers || {}, body]
    end
  end

  after { upstream.stop }

  def fixture(name) = File.binread(File.expand_path("../../../fixtures/media/#{name}", __dir__))

  def get(path, query = '')
    proxy.call('REQUEST_METHOD' => 'GET', 'SCRIPT_NAME' => '/clip', 'PATH_INFO' => path, 'QUERY_STRING' => query)
  end

  def samples(body) = SegmentReader.samples(body, init: fixture('init.mp4'))

  it 'serves the playlist and the decrypted segments of a clip', :aggregate_failures do
    expect(get('/hls/clip.m3u8', 't=1').values_at(0, 2)).to eq([200, [fixture('clip.m3u8')]])
    status, headers, body = get('/hls/segment1.m4s')
    expect([status, headers['content-length']]).to eq([200, body.join.bytesize.to_s])
    expect(samples(body.join)).to eq(samples(fixture('segment1.m4s')))
  end

  it 'rewrites a redirect of the same origin under the mount, and refuses one to another', :aggregate_failures do
    files['/hls/moved.m4s'] = [302, '', { 'Location' => "#{upstream.url}/hls/segment1.m4s?x=1" }]
    files['/hls/away.m4s'] = [302, '', { 'Location' => 'http://evil.test/x' }]
    expect(get('/hls/moved.m4s').then { [it[0], it[1]['location']] }).to eq([302, '/clip/hls/segment1.m4s?x=1'])
    expect(get('/hls/away.m4s')).to eq([502, {}, []])
  end

  it 'answers 404 to a path of another origin, without asking upstream', :aggregate_failures do
    expect(get('//evil.test/x').first).to eq(404)
    expect(upstream.requests).to be_empty
  end

  it 'answers 502, with no body, to a segment that does not decrypt' do
    files['/hls/segment1.m4s'] = [200, FakeCamera.new('a b c d e', 'cam-1').seal_segment(fixture('segment1.m4s'),
                                                                                         cek: Random.bytes(16))]
    expect(get('/hls/segment1.m4s')).to eq([502, {}, []])
  end

  it 'answers 502, with no body, to a playlist that names no init segment or is not one', :aggregate_failures do
    files['/hls/clip.m3u8'] = [200, fixture('clip.m3u8').sub(/^#EXT-X-MAP.*\n/, '')]
    expect(get('/hls/segment1.m4s')).to eq([502, {}, []])
    files['/hls/clip.m3u8'] = [200, 'not a playlist']
    expect(get('/hls/segment1.m4s')).to eq([502, {}, []])
  end

  it 'passes an expired upstream refusal through' do
    files['/hls/clip.m3u8'] = [403, '<Error>expired</Error>']
    expect(get('/hls/clip.m3u8').values_at(0, 2)).to eq([403, ['<Error>expired</Error>']])
  end

  it 'answers 405 to anything but GET' do
    expect(proxy.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => '/hls/clip.m3u8').first).to eq(405)
  end

  it 'serves 20 concurrent segment requests, each with its own samples' do
    paths = Array.new(20) { "/hls/segment#{it % 2}.m4s" }
    bodies = paths.map { |path| Thread.new { get(path)[2].join } }.map(&:value)
    expect(bodies.map { samples(it) }).to eq(paths.map { samples(fixture(File.basename(it))) })
  end
end
