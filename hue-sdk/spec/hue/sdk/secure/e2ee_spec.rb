# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::E2ee do
  let(:passphrase) { 'alpha bravo charlie delta echo' }
  let(:keys) { described_class::Keys.new(passphrase) }
  let(:camera) { FakeCamera.new(passphrase, 'cam-1') }
  let(:cek) { Random.bytes(16) }
  let(:error) { Hue::Sdk::Secure::E2eeError }

  def flipped(bytes, at) = bytes.dup.tap { it.setbyte(at, it.getbyte(at) ^ 1) }

  it 'opens an envelope the camera sealed for the app, and returns what follows it' do
    expect(described_class.open("#{camera.envelope(cek)}rest", keys:, camera_id: 'cam-1')).to eq([cek, 'rest'])
  end

  it 'refuses an envelope another camera sealed' do
    envelope = FakeCamera.new(passphrase, 'cam-2').envelope(cek)
    expect { described_class.open(envelope, keys:, camera_id: 'cam-1') }.to raise_error(error, /camera/)
  end

  it 'refuses an envelope sealed for another passphrase' do
    envelope = FakeCamera.new('foxtrot golf hotel india juliett', 'cam-1').envelope(cek)
    expect { described_class.open(envelope, keys:, camera_id: 'cam-1') }.to raise_error(error, /app/)
  end

  it 'refuses an envelope whose content key the camera did not sign' do
    envelope = camera.envelope(cek, signer: OpenSSL::PKey::EC.generate('prime256v1'))
    expect { described_class.open(envelope, keys:, camera_id: 'cam-1') }.to raise_error(error, /signature/)
  end

  it 'refuses a post-quantum envelope' do
    expect { described_class.open(camera.pqc_envelope, keys:, camera_id: 'cam-1') }
      .to raise_error(error, /post-quantum/)
  end

  it 'refuses an envelope whose tag was changed' do
    expect { described_class.open(flipped(camera.envelope(cek), 243), keys:, camera_id: 'cam-1') }
      .to raise_error(error)
  end

  it 'refuses an envelope cut short' do
    expect { described_class.open(camera.envelope(cek).byteslice(0, 200), keys:, camera_id: 'cam-1') }
      .to raise_error(error)
  end

  it 'decrypts a box, and refuses one with a changed byte', :aggregate_failures do
    box = camera.box(cek, 'jpeg')
    expect(described_class.decrypt(cek, box)).to eq('jpeg')
    expect { described_class.decrypt(cek, flipped(box, 13)) }.to raise_error(error)
  end

  it 'shows neither the passphrase nor a key', :aggregate_failures do
    expect(keys.inspect).to eq('#<Hue::Sdk::Secure::E2ee::Keys>')
    expect(keys.app.inspect).not_to include(keys.app.private_key.to_s(16))
  end
end
