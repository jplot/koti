# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Media do
  include_context 'with the Hue cloud'

  let(:passphrase) { 'alpha bravo charlie delta echo' }
  let(:camera) { FakeCamera.new(passphrase, 'cam-1') }
  let(:cek) { Random.bytes(16) }
  let(:error) { Hue::Sdk::Secure::E2eeError }
  let(:snapshots) { '/security/event-service/v1/home/home-1/device/cam-1/timestamp' }

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

    it 'refuses a snapshot whose image does not decrypt' do
      media = opened
      blob = camera.snapshot_blob('jpeg', cek).tap { it.setbyte(250, it.getbyte(250) ^ 1) }
      answer(snapshot: Base64.strict_encode64(blob), timestamp: '2026-11-13T10:00:00Z')
      expect { media.snapshot('cam-1') }.to raise_error(error)
    end
  end
end
