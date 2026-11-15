# frozen_string_literal: true

RSpec.describe Miele::Sdk::CoffeeMaker do
  subject(:coffee) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { identity('CVA7840') }
  let(:served) do
    { [1, 109, 24_812, 0] => profile(24_812, 'Miele', following: 24_813),
      [1, 109, 24_813, 0] => profile(24_813, 'Anna', following: 24_815), [1, 109, 24_815, 0] => profile(24_815, 'Carl'),
      [1, 109, 24_814, 0] => profile(24_814, ''),
      [1, 109, 24_037, 0] => profile(24_037, 'Kaffee'), [2, 261, 24_037, 0] => drink(255) }
  end
  let(:fake) do
    answers = served
    FakeAppliance.start do |request|
      case request
      in { path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/DOP2/(\d+)/(\d+)\?idx1=(\d+)&idx2=(\d+)\z} }
        key = Regexp.last_match.captures.map(&:to_i)
        [200, {}, answers.fetch(key) { dop2_leaf(key[0], key[1], {}, idx1: key[2], idx2: key[3]) }]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def identity(tech)
    Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 17, 'ProtocolVersion' => 4,
                                                  'DeviceIdentLabel' => { 'TechType' => tech })
  end

  def profile(id, name, following: id, **given)
    values = { program_id: id, type: 10, display: 255, active: true, clear: false }.merge(given)
    fields = { 1 => dop2_field(:u16, values[:program_id]), 2 => dop2_field(:e8, values[:type]),
               3 => dop2_field(:string, name), 4 => dop2_field(:u8, values[:display]),
               5 => dop2_field(:bool, values[:active]),
               6 => dop2_field(:bool, values[:clear]) }
    dop2_leaf(1, 109, fields, idx1: id, idx2: following)
  end

  def drink(brew_speed, **given)
    values = { bean: 1, pre: 0, amount: 33, temperature: 1 }.merge(given)
    fields = { 1 => dop2_field(:e16, 24_037), 2 => dop2_field(:u8, values[:bean]), 3 => dop2_field(:e8, values[:pre]),
               4 => dop2_field(:u8, brew_speed), 5 => dop2_field(:u8, values[:amount]),
               7 => dop2_field(:e8, values[:temperature]),
               8 => dop2_field(:struct_array, [{ 1 => dop2_field(:e8, 3) }]) }
    dop2_leaf(2, 261, fields, idx1: 24_037)
  end

  def written
    fake.requests.select { it.verb == 'PUT' }.map { [it.path.delete_prefix("/Devices/#{fab}/"), it.body] }
  end

  def as_written(leaf, index)
    Miele::Sdk::Dop2.encode(Miele::Sdk::Dop2.decode(leaf).with(attribute: index, idx1: index, idx2: index))
  end

  it 'creates a profile on the first free id, inactive, as the app does' do
    coffee.create_profile('Ben')
    expect(written).to eq([['DOP2/1/109?idx1=24814&idx2=0', as_written(profile(24_814, 'Ben', active: false), 24_814)]])
  end

  it 'tells profiles by the index of their instance, whatever ProgramId says, as the app does' do
    served[[1, 109, 24_813, 0]] = profile(24_813, 'Anna', following: 24_815, program_id: 0)
    coffee.create_profile('Ben')
    expect(written.map(&:first)).to eq(['DOP2/1/109?idx1=24814&idx2=0'])
  end

  it 'renames a profile, a blank, taken or Miele name too, which the app refuses', :aggregate_failures do
    expect(['Ben', 'Anna', '  ', 'Carl', 'miele'].map { coffee.profile_name_allowed?(24_813, it) })
      .to eq([true, true, false, false, false])
    coffee.rename_profile(24_813, 'Ben')
    coffee.rename_profile(24_813, 'Carl')
    expect(written).to eq([['DOP2/1/109?idx1=24813&idx2=0', as_written(profile(24_813, 'Ben'), 24_813)],
                           ['DOP2/1/109?idx1=24813&idx2=0', as_written(profile(24_813, 'Carl'), 24_813)]])
  end

  it 'renames and deletes the standard profile, while the app offers custom ones alone', :aggregate_failures do
    served[[2, 348, 0, 0]] = dop2_leaf(2, 348, { 132 => dop2_field(:struct, { 29 => dop2_field(:bool, true) }) })
    expect(coffee.custom_profiles).to eq((24_813..24_822).to_a)
    expect([coffee.profile_name_allowed?(24_812, 'Ben'), coffee.delete_profile_offered?(24_812)]).to eq([false, false])
    coffee.rename_profile(24_812, 'Ben')
    coffee.delete_profile(24_812)
    expect(written.map(&:first)).to eq(['DOP2/1/109?idx1=24812&idx2=0'] * 2)
  end

  it 'names a drink with a blank name, or one no profile holds, which the app does not', :aggregate_failures do
    expect([coffee.drink_name_allowed?(24_037, ' '), coffee.drink_name_allowed?(23_999, 'Kaffee')])
      .to eq([false, false])
    served[[1, 109, 23_999, 0]] = profile(23_999, 'Tee')
    coffee.rename_drink(24_037, ' ')
    coffee.rename_drink(23_999, 'Kaffee')
    expect(written.map(&:first)).to eq(%w[DOP2/1/109?idx1=24037&idx2=0 DOP2/1/109?idx1=23999&idx2=0])
  end

  it 'deletes a profile though its features list no coffee profiles, which the app requires', :aggregate_failures do
    expect(coffee.delete_profile_offered?(24_813)).to be(false)
    coffee.delete_profile(24_813)
    feature_co = { 29 => dop2_field(:bool, true) }
    served[[2, 348, 0, 0]] = dop2_leaf(2, 348, { 132 => dop2_field(:struct, feature_co) })
    expect(coffee.delete_profile_offered?(24_813)).to be(true)
    expect(written).to eq([['DOP2/1/109?idx1=24813&idx2=0', as_written(profile(24_813, ''), 24_813)]])
  end

  it 'edits a CVA drink and names it, outside the standard profile, as the app does', :aggregate_failures do
    expect(coffee.drink_name_allowed?(24_037, 'Mein Kaffee')).to be(true)
    coffee.edit_drink(24_037, amount: 50, temperature: 2, pre_brewing: 1, bean_sort: 2)
    coffee.rename_drink(24_037, 'Mein Kaffee')
    edited = drink(50, bean: 2, pre: 1, amount: 50, temperature: 2)
    expect(written).to eq([['DOP2/2/261?idx1=24037&idx2=0', as_written(edited, 24_037)],
                           ['DOP2/1/109?idx1=24037&idx2=0', as_written(profile(24_037, 'Mein Kaffee'), 24_037)]])
  end

  it 'names a drink of the standard profile, which the app does not', :aggregate_failures do
    expect(coffee.drink_name_allowed?(24_005, 'Mein Kaffee')).to be(false)
    served[[1, 109, 24_005, 0]] = profile(24_005, 'Espresso')
    coffee.rename_drink(24_005, 'Mein Kaffee')
    expect(written.map(&:first)).to eq(['DOP2/1/109?idx1=24005&idx2=0'])
  end

  it 'keeps a brew speed other than 255, and writes an amount the app does not offer', :aggregate_failures do
    served[[2, 261, 24_037, 0]] = drink(40)
    expect(coffee.drink_settings).to eq(amount: [0, 17, 33, 50, 67, 83, 100], temperature: [0, 1, 2, 3, 4],
                                        pre_brewing: [0, 1, 2])
    coffee.edit_drink(24_037, amount: 40, temperature: 1, pre_brewing: 0, bean_sort: 1)
    expect(written).to eq([['DOP2/2/261?idx1=24037&idx2=0', as_written(drink(40, amount: 40), 24_037)]])
  end

  context 'with a CM6160, which keeps four profiles' do
    let(:ident) { identity('CM6160') }

    it 'finds no free id once the four are used' do
      served[[1, 109, 24_815, 0]] = profile(24_815, 'Carl', following: 24_816)
      served[[1, 109, 24_816, 0]] = profile(24_816, 'Dora', following: 24_814)
      served[[1, 109, 24_814, 0]] = profile(24_814, 'Emil')
      expect { coffee.create_profile('Ben') }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with a CVA Ref2' do
    let(:ident) { identity('CVA7440') }

    it 'writes no bean sort, as the app does, and names a drink, which it does not', :aggregate_failures do
      expect(coffee.drink_name_allowed?(24_037, 'Mein Kaffee')).to be(false)
      coffee.edit_drink(24_037, amount: 50, temperature: 2, pre_brewing: 1, bean_sort: 2)
      coffee.rename_drink(24_037, 'Mein Kaffee')
      expect(written.first).to eq(['DOP2/2/261?idx1=24037&idx2=0',
                                   as_written(drink(50, bean: 255, pre: 1, amount: 50, temperature: 2), 24_037)])
    end
  end

  context 'with a CM7' do
    let(:ident) { identity('CM7550') }

    it 'takes no profile or drink, having no 1/109 or 2/261 object', :aggregate_failures do
      expect { coffee.create_profile('Ben') }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { coffee.rename_drink(24_037, 'Mein Kaffee') }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect([coffee.delete_profile_offered?(24_813), coffee.drink_name_allowed?(24_037, 'Mein Kaffee')])
        .to eq([false, false])
    end
  end
end
