# frozen_string_literal: true

module Miele
  module Sdk
    class WashingMachine < Appliance
      # The parameters the app writes on a washing machine or a washer-dryer: 2/1577's +selection_para_wm+ on
      # DOP2 ({Laundry::Parameters}), 8201's write section on Dop1 ({Dop1Parameters}).
      module Parameters
        COPIED = { delayed_start: %i[delayed_start current_value],
                   delayed_start_mode: %i[delayed_start_mode current_value],
                   temperature: %i[temperatures current_value], temperature_info: %i[temperatures current_value_info],
                   spin_speed: %i[spin_speeds current_value], soiling_degree: %i[soiling_degrees current_value],
                   master_care: %i[master_care_options current_value], cap: %i[caps current_value],
                   preparation_spin_level: %i[preaparation_spin_level current_value],
                   spin_duration: %i[spin_duration current_value], load: %i[load current_value],
                   program_assistent: %i[program_assistant current_value],
                   stains_selection: %i[stains_selection current_value] }.freeze
        # The app copies these on a washer-dryer only.
        WASHER_DRYER_COPIED = { program_mode: %i[program_mode current_value],
                                residual_moisture: %i[residual_moisture current_value],
                                drying_time: %i[drying_time current_value] }.freeze
        DOP2_MEMBERS = { soiling: :soiling_degree, cap: :cap, program_mode: :program_mode }.freeze
        private_constant :COPIED, :WASHER_DRYER_COPIED, :DOP2_MEMBERS

        private

        # @return [Symbol]
        def para_member = :selection_para_wm

        # @return [Array<Symbol>]
        def parameter_names
          return %i[temperature eco spin_speed soiling cap master_care extras stains twin_dos] unless dop2?

          %i[temperature eco spin_speed soiling cap extras stains drying_level drying_time program_mode twin_dos]
        end

        # @return [Hash{Symbol=>Array<Symbol>}]
        def setting_choices
          { extras: dop2? ? DOP2_EXTRAS : DOP1_EXTRAS.keys, stains: STAINS.keys,
            drying_level: Laundry::DRYING_LEVELS.keys }
        end

        # @param para [Objects::Laundry::GlobalPsSelectionParaWM]
        # @param source [Objects::Laundry::GlobalPsContextParaWM]
        # @return [Objects::Laundry::GlobalPsSelectionParaWM]
        def appliance_values(para, source)
          para = copied(para, source, identity.device_type == 24 ? COPIED.merge(WASHER_DRYER_COPIED) : COPIED)
          extras = DOP2_EXTRAS.to_h { [it, [it, :current_value]] }
          para = para.with(extras: copied(para.extras, source.extras, extras)) if para.extras && source.extras
          with_dosing(para, source.auto_dosing)
        end

        # @param para [Objects::Laundry::GlobalPsSelectionParaWM]
        # @param source [Objects::Laundry::GlobalPsContextAutoDosing, nil]
        # @return [Objects::Laundry::GlobalPsSelectionParaWM] each container at the current value 2/1574 shows
        def with_dosing(para, source)
          containers = para.auto_dosing&.container
          return para unless containers && source

          current = source.container.to_a.map(&:current_value)
          containers = containers.each_index.map { current[it] || containers[it] }
          para.with(auto_dosing: para.auto_dosing.with(container: containers))
        end

        # @param para [Objects::Laundry::GlobalPsSelectionParaWM]
        # @param settings [Hash{Symbol=>Object}]
        # @return [Objects::Laundry::GlobalPsSelectionParaWM]
        def dop2_parameters(para, settings)
          para = para.with(extras: chosen(para.extras, settings[:extras], DOP2_EXTRAS)) if settings.key?(:extras)
          if settings.key?(:twin_dos)
            raise ArgumentError, 'twin_dos: 2/1577 carries no auto_dosing' unless para.auto_dosing

            para = para.with(auto_dosing: para.auto_dosing.with(container: settings[:twin_dos]))
          end
          para.with(**with_temperature(dop2_values(settings, para), settings))
        end

        # The app writes the drying time only where 2/1577 carries it.
        #
        # @param settings [Hash{Symbol=>Object}]
        # @param para [Objects::Laundry::GlobalPsSelectionParaWM]
        # @return [Hash{Symbol=>Object}]
        def dop2_values(settings, para)
          values = settings.slice(*DOP2_MEMBERS.keys).transform_keys(DOP2_MEMBERS).merge(dop2_conversions(settings))
          values[:drying_time] = settings[:drying_time] if settings.key?(:drying_time) && !para.drying_time.nil?
          values
        end

        # The spin speed in tens of rpm, the stains as their flags, the drying level as its flag.
        #
        # @param settings [Hash{Symbol=>Object}]
        # @return [Hash{Symbol=>Integer}]
        def dop2_conversions(settings)
          { spin_speed: settings[:spin_speed]&.div(10),
            stains_selection: settings[:stains]&.sum { STAINS.fetch(it).first },
            residual_moisture: Laundry::DRYING_LEVELS[settings[:drying_level]] }.compact
        end

        # TemperatureInfo: 2 for a cold wash, 1 for an eco temperature, 0 otherwise.
        #
        # @param values [Hash{Symbol=>Object}]
        # @param settings [Hash{Symbol=>Object}]
        # @return [Hash{Symbol=>Object}]
        def with_temperature(values, settings)
          temperature = settings[:temperature]
          return values if temperature.nil?

          info = settings[:eco] ? 1 : 0
          values.merge(temperature:, temperature_info: temperature.zero? ? 2 : info)
        end
      end
    end
  end
end
