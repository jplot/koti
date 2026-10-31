# frozen_string_literal: true

require_relative '../../../schema/generate/model'

RSpec.describe Schema::Generate::Model do
  let(:naming) { Schema::Generate::Naming }

  def model(*dop2) = described_class.new('dop2' => dop2, 'dop1' => [], 'enums' => [])

  def dop2(name, *fields) = { 'family' => 'oven', 'name' => name, 'fields' => fields, 'addresses' => [] }

  def field(name, index) = { 'index' => index, 'name' => name, 'kind' => 'scalar', 'wire' => 5, 'type' => nil }

  it 'names a family module and an object constant from the app names', :aggregate_failures do
    expect(naming.constant('coffee_gen7')).to eq('CoffeeGen7')
    expect(naming.constant('GLOBAL_PS_Select')).to eq('GlobalPsSelect')
    expect(naming.constant('ServiceDataExt_Lueftersteuerung')).to eq('ServiceDataExtLueftersteuerung')
    expect(naming.constant('DeviceState/TempControlSection/Kochstelle_1'))
      .to eq('DeviceState::TempControlSection::Kochstelle1')
  end

  it 'names a member in snake_case from its getter' do
    expect(%w[ProgId Struktur_Version KFBELDimmwert Remaining_time__s_].map { naming.member(it) })
      .to eq(%i[prog_id struktur_version kfbel_dimmwert remaining_time_s])
  end

  it 'adds a final _ to a member a value class already has' do
    expect(naming.member('ObjectID')).to eq(:object_id_)
  end

  it 'spells a German letter out in ASCII', :aggregate_failures do
    expect(naming.constant('BestätigungNotwendigEnum')).to eq('BestaetigungNotwendigEnum')
    expect(naming.member('Topfgroeße_erkannt_Variokochzone_1').to_s).to eq('topfgroesse_erkannt_variokochzone_1')
  end

  it 'shortens enum values by the prefix they share' do
    values = [['GLOBAL_DS_MAINSTATEEXTERN_RESERVED_NO_USE', 0], ['GLOBAL_DS_MAINSTATEEXTERN_RUNNING', 5]]
    expect(naming.symbols('Hob::GlobalEnumMainStateExtern', values)).to eq(%i[reserved_no_use running])
  end

  it 'shortens them by the prefix the values but 0 share, when two of them do', :aggregate_failures do
    booster = [['aus', 0], ['Booster_1', 1], ['Booster_2', 2]]
    pot = [['mit_Topferkennung', 0], ['ohne_Topferkennung', 1]]
    expect(naming.symbols('Hob::BoosterEnum', booster)).to eq(%i[aus 1 2])
    expect(naming.symbols('Hob::TopferkennungsEnum', pot)).to eq(%i[mit_topferkennung ohne_topferkennung])
  end

  it 'keeps the underscores that tell two enum values apart' do
    values = [['Kochstufe_1', 1], ['Kochstufe_1_', 2], ['Restwaerme_H', 100]]
    expect(naming.symbols('Hob::KochstufeDeviceStateEnum', values).map(&:to_s))
      .to eq(%w[kochstufe_1 kochstufe_1_ restwaerme_h])
  end

  it 'refuses two objects of a family under one constant' do
    expect { model(dop2('GLOBAL_PS_Select'), dop2('GLOBAL_PS_SELECT')) }
      .to raise_error(ArgumentError, /Oven::GlobalPsSelect/)
  end

  it 'refuses two fields of an object under one member' do
    expect { model(dop2('GLOBAL_PS_Select', field('Remaining_time__s_', 1), field('RemainingTime_s', 2))) }
      .to raise_error(ArgumentError, /remaining_time_s/)
  end

  describe 'the extracted file' do
    let(:objects) { described_class.load(File.join(__dir__, '../../../lib/miele/sdk/objects/objects.json.gz')) }

    def oven(constant) = objects.dop2.find { it.constant == "Oven::#{constant}" }

    it 'gives every object a distinct constant' do
      expect((objects.dop2 + objects.dop1 + objects.enums).map(&:constant).uniq.size).to eq(402 + 468 + 336)
    end

    it 'names a field type by the constant of its class or enum' do
      expect(oven('GlobalPsSelect').fields.find { it.member == :selection_type }.type)
        .to eq('Oven::GlobalEnumSelectionType')
    end

    it 'names a Dop1 section by the constant of its class' do
      object = objects.dop1.find { it.constant == 'Hood::ServiceDataExtLueftersteuerung' }
      expect(object.sections.map(&:type))
        .to eq(['Hood::ServiceDataExtLueftersteuerung::ServiceDataExtLueftersteuerungSection'])
    end

    it 'keeps two getters on one index under two names' do
      expect(oven('GlobalPsAttributesCCA').fields.select { it.index == 5 }.map(&:member))
        .to contain_exactly(:total_remaining_time, :level)
    end
  end
end
