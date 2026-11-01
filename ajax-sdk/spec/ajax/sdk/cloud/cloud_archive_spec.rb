# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::CloudArchive do
  let(:client) { Ajax::Sdk::Cloud::Client.new(settings) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'local', grpc_port: 0, read_timeout: 0.2,
                                                        ca_file: nil, read_only: true, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:gateway) { FakeGateway.start({ path => calls }) }

  before do
    allow(GRPC::ClientStub).to receive(:new).and_wrap_original do |original, *, **options|
      original.call("127.0.0.1:#{gateway.port}", :this_channel_is_insecure, **options)
    end
    allow(client.session).to receive_messages(ensure_login: nil, login: nil, metadata: {})
  end

  after { gateway.stop }

  def service = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service'

  def channel
    Ajax::Sdk::Cloud::VideoChannel.new(space_id: 's1', video_edge_id: '0000ABCD', channel_id: 'ch-1', ptz: false,
                                       sub_stream: true, sound: true, raw: nil)
  end

  def where = { space_id: 's1', video_edge_id: '0000ABCD', channel_id: 'ch-1' }

  def sent = gateway.requests.map { |_path, request| request }

  context 'with video' do
    let(:path) do
      "#{service}.stream_cloud_archive_video_fragments_content.StreamCloudArchiveVideoFragmentsContentService/execute"
    end
    let(:calls) { [[:read, :read, whole, :read, part]] }

    def whole
      { success: { fragment_content: { tag: '1', fragment_id: 42, content_url: 'https://cdn.example.com/42' } } }
    end

    def part
      header = { key: 'Range', value: 'bytes=0-' }
      { success: { fragment_part_content: { tag: '2', fragment_id: 43, offset: 1_500_000, content_url_headers: [header],
                                            content_url: 'https://cdn.example.com/43' } } }
    end

    def play(archive)
      tags = [archive.get(42)]
      received = []
      archive.each do |content|
        received << content
        tags << archive.get_part(43, 1.5) if received.one?
      end
      [tags, received]
    end

    it 'asks after the init, each request tagged, and gives the addresses', :aggregate_failures do
      tags, received = play(client.cloud_archive(channel, quality: :sub))

      expect(tags).to eq(%w[1 2])
      expect(received.map { [it.tag, it.content_url] })
        .to eq([%w[1 https://cdn.example.com/42], %w[2 https://cdn.example.com/43]])
      expect(received.last.content_url_headers.map { [it.key, it.value] }).to eq([%w[Range bytes=0-]])
    end

    it 'sends the init, whole fragments and a part from its offset in microseconds' do
      play(client.cloud_archive(channel, quality: :sub))
      part = { fragment_part: { fragment_id: 43, offset: 1_500_000 } }
      whole = { fragment_id: 42 }

      expect(sent).to eq([{ init: { **where, stream_type: :ST_SUB } },
                          { get: { tag: '1', entries: [whole] } }, { get: { tag: '2', entries: [part] } }])
    end
  end

  context 'with metadata' do
    let(:path) do
      "#{service}.stream_cloud_archive_metadata_fragments_content." \
        'StreamCloudArchiveMetadataFragmentsContentService/execute'
    end
    let(:calls) { [%i[read read]] }

    it 'sends the init with the metadata type, then whole fragments' do
      archive = client.cloud_metadata(channel, type: 'A')
      archive.get(7, 8)
      archive.each { nil }

      expect(sent).to eq([{ init: { **where, metadata_type: 'A' } },
                          { get: { tag: '1', entries: [{ fragment_id: 7 }, { fragment_id: 8 }] } }])
    end
  end

  context 'when the playback limit is reached' do
    let(:path) do
      "#{service}.stream_cloud_archive_video_fragments_content.StreamCloudArchiveVideoFragmentsContentService/execute"
    end
    let(:calls) { [[:read, { failure: { playback_limit_exceeded: {} } }]] }

    it 'raises the reason' do
      expect { client.cloud_archive(channel).each { nil } }
        .to raise_error(Ajax::Sdk::Cloud::ReadError, 'playback_limit_exceeded')
    end
  end
end
