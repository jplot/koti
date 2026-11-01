# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::CloudArchive do
  let(:client) { Ajax::Sdk::Cloud::Client.new(settings) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'local', grpc_port: 0, read_timeout: 0.2,
                                                        ca_file: nil, read_only: true, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:path) { video }
  let(:gateway) { FakeGateway.start({ path => calls }) }

  before do
    allow(GRPC::ClientStub).to receive(:new).and_wrap_original do |original, *, **options|
      original.call("127.0.0.1:#{gateway.port}", :this_channel_is_insecure, **options)
    end
    allow(client.session).to receive_messages(ensure_login: nil, login: nil, metadata: {})
  end

  after { gateway.stop }

  def service = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service'

  def video
    "#{service}.stream_cloud_archive_video_fragments_content.StreamCloudArchiveVideoFragmentsContentService/execute"
  end

  def metadata
    "#{service}.stream_cloud_archive_metadata_fragments_content." \
      'StreamCloudArchiveMetadataFragmentsContentService/execute'
  end

  def channel
    Ajax::Sdk::Cloud::VideoChannel.new(space_id: 's1', video_edge_id: '0000ABCD', channel_id: 'ch-1', ptz: false,
                                       sub_stream: true, sound: true, raw: nil)
  end

  def where = { space_id: 's1', video_edge_id: '0000ABCD', channel_id: 'ch-1' }

  def sent = gateway.requests.map { |_path, request| request }

  context 'with video' do
    let(:calls) { [[:read, :read, whole, :read, part, :read]] }

    def whole
      { success: { fragment_content: { tag: '-1', fragment_id: 42, content_url: 'https://cdn.example.com/42' } } }
    end

    def part
      content = { tag: '-1', fragment_id: 43, offset: 1_001_000, content_url: 'https://cdn.example.com/43',
                  content_url_headers: [{ key: 'Range', value: 'bytes=0-' }] }
      { success: { fragment_part_content: content } }
    end

    def play(archive)
      tags = [archive.get(42)]
      received = []
      archive.each do |content|
        received << content
        tags.push(archive.get_part(43, 1.001)) if received.one?
        tags.push(archive.seek, archive.get(44)) if received.size == 2
      end
      [tags, received]
    end

    it 'tags each request with the current generation, which a seek moves on, as the app does' do
      expect(play(client.cloud_archive(channel, quality: :sub)).first).to eq(%w[-1 -1 0 0])
    end

    it 'gives the addresses, with the headers a part is fetched with', :aggregate_failures do
      received = play(client.cloud_archive(channel)).last
      addresses = [%w[-1 https://cdn.example.com/42], %w[-1 https://cdn.example.com/43]]

      expect(received.map { [it.tag, it.content_url] }).to eq(addresses)
      expect(received.last.content_url_headers.map { [it.key, it.value] }).to eq([%w[Range bytes=0-]])
    end

    it 'sends the init, whole fragments and a part from its offset, in whole milliseconds' do
      play(client.cloud_archive(channel, quality: :sub))
      gets = [['-1', { fragment_id: 42 }], ['-1', { fragment_part: { fragment_id: 43, offset: 1_001_000 } }],
              ['0', { fragment_id: 44 }]].map { |tag, entry| { get: { tag:, entries: [entry] } } }

      expect(sent).to eq([{ init: { **where, stream_type: :ST_SUB } }, *gets])
    end
  end

  context 'with an empty answer' do
    let(:calls) { [[:read, { success: {} }, { success: { init: {} } }]] }

    it 'leaves it out' do
      expect(client.cloud_archive(channel).each.to_a)
        .to contain_exactly(have_attributes(playback_duration_interval: nil))
    end
  end

  context 'with metadata' do
    let(:path) { metadata }
    let(:calls) { [%i[read read read]] }

    it 'sends the init with the metadata type, then each request under the next tag from 0', :aggregate_failures do
      archive = client.cloud_metadata(channel, type: 'Figures')
      tags = [archive.get(7, 8), archive.get(9)]
      archive.each { nil }

      expect(tags).to eq(%w[0 1])
      expect(sent).to eq([{ init: { **where, metadata_type: 'Figures' } },
                          { get: { tag: '0', entries: [{ fragment_id: 7 }, { fragment_id: 8 }] } },
                          { get: { tag: '1', entries: [{ fragment_id: 9 }] } }])
    end
  end

  context 'when the playback limit is reached' do
    let(:calls) { [[:read, { failure: { playback_limit_exceeded: {} } }]] }

    it 'raises the reason' do
      expect { client.cloud_archive(channel).each { nil } }
        .to raise_error(Ajax::Sdk::Cloud::ReadError, 'playback_limit_exceeded')
    end
  end

  describe '.days' do
    let(:calls) { [] }

    def start = Time.utc(2026, 10, 1).to_i

    def calendar(days, *tz_map)
      tz_map = tz_map.map { |day, offsets| { day: { seconds: start + (day * 86_400) }, offsets: } }
      Ajax::Sdk::Cloud::Messages::Api::Mobile::V2::Common::Video::Videoedge::Archive::Calendar
        .from({ start_day: { seconds: start }, days: days.pack('C*'), tz_map: })
    end

    def date(day) = Date.new(2026, 10, day)

    it 'reads the recorded days in the app order, once each, without the empty ones or those before any entry' do
      days = described_class.days(calendar([1, 1, 0, 1], [1, [0]], [3, [0, -3, -2]]))

      expect(days).to eq([date(2), date(4), date(1)])
    end

    it 'takes the last of the entries of the same day, as the app sorts them stably' do
      entries = Array.new(18) { [it % 2, it == 17 ? [1] : [0]] }

      expect(described_class.days(calendar([0, 1], *entries))).to eq([date(3)])
    end

    it 'gives the dates in UTC whatever the local zone' do
      zone = ENV.fetch('TZ', nil)
      ENV['TZ'] = 'America/New_York'

      expect(described_class.days(calendar([1], [0, [0]]))).to eq([date(1)])
    ensure
      ENV['TZ'] = zone
    end
  end
end
