# frozen_string_literal: true

module Miele
  module Sdk
    class WashingMachine < Appliance
      # The parameters the app writes on a Dop1 washing machine, on 8201's write section ({Laundry::Parameters}).
      module Dop1Parameters
        DOP1_MEMBERS = { spin_speed: :drehzahl, soiling: :verschmutzungsgrad, cap: :kapseldosierung,
                         master_care: :mastercare }.freeze
        ECO_TEMPERATURES = { 40 => 39, 60 => 59 }.freeze
        private_constant :DOP1_MEMBERS, :ECO_TEMPERATURES

        private

        # The app copies every active parameter and every named extras bit, the reserve left 0.
        #
        # @param current [Objects::Laundry::WaProgrammwahlSetzen] 8201 as read
        # @param settings [Hash{Symbol=>Object}]
        # @return [Data] 8201's write section
        def dop1_parameters(current, settings)
          active = current.aktive_parameter
          section = blank(Objects::Laundry::WaProgrammwahlSetzen::SettingsWriteSection)
          changes = dop1_bits(settings)
          copied = section.members - %i[extras_bit_field0 extras_bit_field1 bytes endian]
          section.with(**active.to_h.slice(*copied), **dop1_values(settings),
                       extras_bit_field0: bits(section.extras_bit_field0, active.extras_bit_field0, changes),
                       extras_bit_field1: bits(section.extras_bit_field1, active.extras_bit_field1, changes))
        end

        # The app writes the TwinDos containers only when given both.
        #
        # @param settings [Hash{Symbol=>Object}]
        # @return [Hash{Symbol=>Object}]
        def dop1_values(settings)
          values = settings.slice(*DOP1_MEMBERS.keys).transform_keys(DOP1_MEMBERS)
          values[:temperatur] = dop1_temperature(settings[:temperature], settings[:eco]) if settings.key?(:temperature)
          twin_dos = settings[:twin_dos]
          return values unless twin_dos&.size == 2

          values.merge(twin_dos.each_with_index.to_h { |value, index| [:"auto_dos_behaelter_#{index + 1}", value] })
        end

        # The app writes 20 to 95 °C in steps of 5, an eco 40 or 60 °C as 39 or 59, and 0 for anything else.
        #
        # @param temperature [Integer]
        # @param eco [Boolean, nil]
        # @return [Integer]
        def dop1_temperature(temperature, eco)
          return ECO_TEMPERATURES.fetch(temperature, 0) if eco

          (20..95).step(5).include?(temperature) ? temperature : 0
        end

        # @param settings [Hash{Symbol=>Object}]
        # @return [Hash{Symbol=>Integer}] each extras and stains bit set or cleared
        def dop1_bits(settings)
          extras, stains = settings.values_at(:extras, :stains)
          (DOP1_EXTRAS.filter_map { |name, bit| [bit, extras.include?(name) ? 1 : 0] if extras } +
            STAINS.filter_map { |name, (_, bit)| [bit, stains.include?(name) ? 1 : 0] if stains }).to_h
        end

        # @param field [Data] a blank extras bit field of the write section
        # @param source [Data] its active counterpart
        # @param changes [Hash{Symbol=>Integer}]
        # @return [Data]
        def bits(field, source, changes)
          names = field.members - %i[bytes endian reserve]
          field.with(**source.to_h.slice(*names), **changes.slice(*names))
        end
      end
    end
  end
end
