# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Streams do
  let(:channel) do
    Ajax::Sdk::Cloud::VideoChannel.new(space_id: 's1', video_edge_id: '0000ABCD', channel_id: 'ch-1', ptz: true,
                                       sub_stream: true, sound: true, raw: nil)
  end

  def view(number, quality = :main) = described_class::View.new(channel:, number:, quality:)

  def frame(type, name = '') = { frame_type: type, metadata_type: name }

  def seconds(value) = { seconds: value, nanos: 0 }

  def source(id, tag, type = :ST_MAIN) = { id:, channel_guid: 'ch-1', dcp_tag: tag, type: }

  it 'asks for live video with the metadata named and PTZ' do
    stream = described_class.live(view(2, :sub), tag: 5, metadata: %w[Figures A], ptz: true)

    expect(stream.to_message).to eq(
      **source('2-ls', 5, :ST_SUB), live: { input_rtc_stream_id: '', use_ptz: true },
                                    filter: [frame(:FT_VIDEO), frame(:FT_METADATA, 'Figures'), frame(:FT_METADATA, 'A')]
    )
  end

  it 'asks for the metadata in the order the app does, and no other' do
    stream = described_class.live(view(2), tag: 5, metadata: %w[RadarMotion Figures Figures])

    expect(stream.to_message[:filter].map { it[:metadata_type] }).to eq(['', 'Figures', 'RadarMotion'])
  end

  it 'refuses metadata the app never asks a live stream for' do
    expect { described_class.live(view(2), tag: 5, metadata: %w[Thumbnail]) }.to raise_error(ArgumentError, /Thumbnail/)
  end

  it 'asks for the live sound, with talk-back on the voice stream' do
    stream = described_class.audio(view(2), tag: 6, talk_back: true)

    expect(stream.to_message).to eq(
      **source('2-l', 6), filter: [frame(:FT_AUDIO)], live: { input_rtc_stream_id: 'voice', use_ptz: false }
    )
  end

  it 'asks for no audio frame when the sound is off' do
    expect(described_class.audio(view(2), tag: 6, sound: false).to_message[:filter]).to eq([])
  end

  it 'asks for the archive in whole seconds, its position every second' do
    during = Time.at(100.9)..Time.at(200.2)
    stream = described_class.archive(view(3), tag: 7, during:, sound: true, figures: true)
    archive = { ts_range: { min_value: seconds(100), max_value: seconds(200) }, pos_update_interval: seconds(1) }

    expect(stream.to_message).to eq(
      **source('3-a', 7), archive: { **archive, group_id: '' },
                          filter: [frame(:FT_VIDEO), frame(:FT_AUDIO), frame(:FT_METADATA, 'Figures')]
    )
  end

  it 'asks for the activity of a time range, without video' do
    stream = described_class.activity(view(3), tag: 8, during: Time.at(100)..Time.at(200))
    archive = { ts_range: { min_value: seconds(100), max_value: seconds(200) }, group_id: '' }

    expect(stream.to_message).to eq(**source('3-activity', 8), filter: [frame(:FT_METADATA, 'A')], archive:)
  end

  it 'asks for the live thumbnails on the sub stream, whatever the view' do
    stream = described_class.preview(view(4), tag: 9)

    expect(stream.to_message).to eq(
      **source('4-live-preview', 9, :ST_SUB), filter: [frame(:FT_METADATA, 'Thumbnail')],
                                              live: { input_rtc_stream_id: '', use_ptz: false }
    )
  end
end
