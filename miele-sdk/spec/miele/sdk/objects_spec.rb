# frozen_string_literal: true

RSpec.describe Miele::Sdk::Objects do
  def field(type, value) = Miele::Sdk::Dop2::Field.new(type:, value:)

  def named(object)
    return [] unless object.is_a?(Class)

    nested = object.constants(false).map { object.const_get(it) }.grep(Class)
    [*object::MEMBERS.values.flat_map { it.grep(String) }, *nested.flat_map { named(it) }]
  end

  describe 'a DOP2 object' do
    let(:steps) { described_class::Oven::GlobalOpProgramInfoCA }

    it 'reads the oven program steps as a typed value' do
      value = steps.from(1 => field(:u8, 3), 2 => field(:u8, 1), 4 => field(:e16_array, [1, 2]))
      expect(value).to have_attributes(amount_of_steps: 3, current_step: 1,
                                       infos1: %i[alle_funktionen_wurden_in_den_auslieferungszu beliebige_ebene])
    end

    it 'keeps an enum value the app does not know as its Integer' do
      expect(steps.from(4 => field(:e16_array, [2, 65_000])).infos1).to eq([:beliebige_ebene, 65_000])
    end

    it 'reads an absent attribute as nil' do
      expect(steps.from(1 => field(:u8, 3))).to have_attributes(edit_status: nil, infos2: nil)
    end
  end

  describe 'a DOP2 write' do
    let(:select) { described_class::Oven::GlobalPsSelect.from(1 => field(:e16, 1), 3 => field(:e8, 0)) }

    it 'writes back what it read, with one member changed' do
      fields = select.with(selection_type: :parametrization).to_fields
      leaf = Miele::Sdk::Dop2::Leaf.new(unit: 2, attribute: 1577, idx1: 0, idx2: 0, fields:)
      expect(Miele::Sdk::Dop2.encode(leaf).unpack1('H*')).to eq('001300020629000000000002000107000100030402')
    end

    it "refuses to change a member it did not read, as the app's setters do" do
      expect { select.with(selection_parameter: 6).to_fields }.to raise_error(ArgumentError, /selection_parameter/)
    end
  end

  describe 'a Dop1 object' do
    let(:selection) { described_class::Dishwasher::SmartControlGsdProgrammwahlSetzen.from(bytes) }
    let(:bytes) { [1, 5, 0x05, 0x80].pack('C*') + ("\0" * 11) }

    it 'decodes a Dop1 object with bit fields in its endianness' do
      expect(selection.settings_write.extras_bit_field)
        .to have_attributes(extra_kurz: :ein, extra_sparsam: :aus, extra_trocken: :ein, reserve: 256)
    end

    it "writes a Dop1 write section as the app's GenerateWriteBytes" do
      expect(selection.settings_write.with(programm_id: :programm_eco).to_bytes).to eq([1, 3, 0x05, 0x80].pack('C4'))
    end
  end

  it 'loads every generated object, and every type its members name' do
    directories = Dir[File.join(__dir__, '../../../lib/miele/sdk/objects/*/')]
    families = directories.map { described_class.const_get(File.basename(it).split('_').map(&:capitalize).join) }
    objects = families.flat_map { |family| family.constants.map { family.const_get(it) } }
    expect(objects.flat_map { named(it) }.reject { described_class.const_defined?(it) }).to be_empty
  end
end
