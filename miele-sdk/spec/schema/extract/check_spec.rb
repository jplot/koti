# frozen_string_literal: true

require_relative '../../../schema/extract/check'

RSpec.describe Schema::Extract::Check do
  subject(:check) { described_class.new(app) }

  let(:bluetooth) { described_class::BORROWED.fetch('ModuleUpdateInfo').keys.first }
  let(:app) do
    described_class::CLASSES.to_h do |name, app_class|
      value = Miele::Sdk::Schema.const_get(name)
      [app_class, { 'fields' => fields_of(value), 'extension' => !value.extension_member.nil? }]
    end.merge(bluetooth => { 'fields' => {}, 'extension' => false })
  end

  def fields_of(value)
    value.json_keys.except(value.extension_member).to_h do |member, key|
      [key, { 'type' => 'string', 'nullable' => value.optional_members.include?(member) }]
    end
  end

  def app_class(name) = app.fetch(described_class::CLASSES.fetch(name))

  it 'checks every typed value of Miele::Sdk::Schema' do
    values = Miele::Sdk::Schema.constants.select do |name|
      Miele::Sdk::Schema.const_get(name).is_a?(Miele::Sdk::Schema::Value::ClassMethods)
    end
    expect(described_class::CLASSES.keys.map(&:to_sym)).to match_array(values)
  end

  it 'finds nothing when every app class matches its typed value' do
    expect(check.differences).to be_empty
  end

  it 'reports a key the app adds or drops' do
    app_class('DeviceState')['fields'].delete('ProgramID')
    app_class('DeviceState')['fields']['Pause'] = { 'type' => 'bool', 'nullable' => false }
    expect(check.differences).to eq(['DeviceState: the app adds Pause', 'DeviceState: the app drops ProgramID'])
  end

  it 'reports a member whose optionality differs from the nullability of its key' do
    app_class('SuperVisionDevice')['fields'].each_value { it['nullable'] = !it['nullable'] }
    expect(check.differences).to eq(['SuperVisionDevice#show is required, but the app lets Show be null',
                                     'SuperVisionDevice#signal is optional, but the app never leaves Signal null'])
  end

  it 'takes only the keys it borrows from another app class, as keys the answer may lack' do
    release_notes = app_class('ModuleUpdateInfo')['fields'].delete('ReleaseNotes').merge('nullable' => false)
    app.fetch(bluetooth)['fields'].merge!('ReleaseNotes' => release_notes, 'Status' => release_notes)
    expect(check.differences).to be_empty
  end

  it 'reports a class whose keys only one side gathers' do
    app_class('SuperVision')['extension'] = false
    app_class('DeviceState')['extension'] = true
    expect(check.differences).to eq(['DeviceState: the app class gathers the other keys, but no member keeps them',
                                     'SuperVision#entries gathers the other keys, but the app class does not'])
  end

  it 'reports an app class it cannot find' do
    app.delete(bluetooth)
    expect(check.differences).to eq(["ModuleUpdateInfo: no app class #{bluetooth}"])
  end
end
