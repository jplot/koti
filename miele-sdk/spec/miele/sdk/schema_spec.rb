# frozen_string_literal: true

RSpec.describe Miele::Sdk::Schema do
  let(:ident) do
    { 'DeviceType' => 13, 'CECEDType' => 0, 'XKMSupport' => 7, 'ProtocolVersion' => 4,
      'DeviceIdentLabel' => { 'FabNumber' => '000123456789', 'TechType' => 'H7164BP', 'SWIDs' => [1, 2] },
      'XKMIdentLabel' => { 'TechType' => 'EK057', 'ReleaseVersion' => '31.17' }, 'Future' => 1 }
  end

  it 'builds a value with its nested values from the keys the appliance sends', :aggregate_failures do
    value = described_class::DeviceIdentification.from(ident)
    expect(value).to have_attributes(device_type: 13, ceced_type: 0, xkm_support: 7, protocol_version: 4)
    expect(value.device_ident_label).to have_attributes(fab_number: '000123456789', sw_ids: [1, 2])
    expect(value.xkm_ident_label).to have_attributes(tech_type: 'EK057', release_version: '31.17')
  end

  it 'leaves the fields the appliance did not send nil' do
    expect(described_class::DeviceState.from('Status' => 5).ventilation_step).to be_nil
  end

  it 'reads the program id under the key the appliance spells' do
    expect(described_class::DeviceState.from('ProgramID' => 13).program_id).to eq(13)
  end

  it 'keeps the peers of a supervision apart from its settings' do
    value = described_class::SuperVision.from('Enabled' => true, 'ErrorOnly' => false,
                                              '000111222333' => { 'href' => '000111222333/' })
    expect(value).to have_attributes(enabled: true, error_only: false,
                                     entries: { '000111222333' => { 'href' => '000111222333/' } })
  end

  it 'rejects a field the app does not know' do
    expect { described_class::SuperVisionDevice.new(show: true, shown: true) }
      .to raise_error(ArgumentError, /unknown keyword: :shown/)
  end

  it 'requires the fields the app never leaves out' do
    expect { described_class::SuperVisionDevice.new(signal: true) }
      .to raise_error(ArgumentError, /missing keyword: :show/)
  end

  it 'refuses a body whose required field is nil' do
    expect { described_class::SuperVisionDevice.new(show: nil).to_body }.to raise_error(ArgumentError, /show/)
  end

  it 'turns a request into a body under the keys of the appliance, without its empty fields' do
    expect(described_class::DeviceState.new(process_action: 1).to_body).to eq('ProcessAction' => 1)
  end

  it 'turns a value back into the JSON it came from', :aggregate_failures do
    expect(JSON.parse(described_class::DeviceIdentification.from(ident).to_json)).to eq(ident.except('Future'))
    supervision = { 'Enabled' => true, 'ErrorOnly' => false, '000111222333' => { 'href' => '000111222333/' } }
    expect(described_class::SuperVision.from(supervision).to_body).to eq(supervision)
  end
end
