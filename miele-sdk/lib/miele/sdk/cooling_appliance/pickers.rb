# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The values the app's refrigeration pickers offer, the only ones it sends.
      module Pickers
        # The °C each Opcode zone subtype offers, as AvailableZonesForOpCodeSource fixes them; nil offers only the
        # zone's current target.
        OPCODE_TARGETS = { kfn: { fridge: 3..9, freezer: -26..-15, wine: 5..20, none: 5..20 },
                           other: { fridge: 2..9, freezer: -28..-14, wine: 5..20, none: nil } }.freeze
        FN_TECH_TYPES = ['FN 30402 i', 'FN 35402 i'].freeze
        KFN_TECH_TYPE = /KFN 37692 iDE|K 3.473 iD/
        private_constant :OPCODE_TARGETS, :FN_TECH_TYPES, :KFN_TECH_TYPE

        private

        # @param value [Integer]
        # @param choices [Array<Integer>]
        # @return [void]
        # @raise [ArgumentError] unless +value+ is one of +choices+
        def require_offered!(value, choices)
          raise ArgumentError, "the app offers #{choices.uniq}, not #{value}" unless choices.include?(value)
        end

        # @param zone [Zone]
        # @param state [State]
        # @return [Array<Integer>] the whole degrees the app's picker offers, rounded half away from zero as it
        #   shows them
        def target_choices(zone, state)
          return opcode_targets(zone, state) if opcode?

          api_targets(device("Cooling/#{zone.number}")['TargetTemp'].to_h).map { it.fdiv(100).round }
        end

        # @param target [Hash{String=>Object}] a zone's +TargetTemp+
        # @return [Array<Integer>] in hundredths: +AllValues+, else +Min+ to +Max+ by +Step+, else the current value
        def api_targets(target)
          return target['AllValues'] if target['AllValues']

          target['Min'].to_i < target['Max'].to_i ? picker(target) : [target['Value']].compact
        end

        # .NET's remainder by a +Step+ of 0 throws, so such a picker offers nothing.
        #
        # @param setting [Hash{String=>Object}, nil] a +Cooling+ setting with +Min+, +Max+ and +Step+
        # @return [Array<Integer>] +Min+ to +Max+ by +Step+, as the app's pickers list them
        def picker(setting)
          min, max, step = setting.to_h.values_at('Min', 'Max', 'Step').map(&:to_i)
          step.zero? ? [] : (min..max).select { ((it - min) % step).zero? }
        end

        # @param zone [Zone]
        # @param state [State]
        # @return [Array<Integer>] whole °C
        def opcode_targets(zone, state)
          return (-28..-15).to_a if FN_TECH_TYPES.include?(tech_type)

          ranges = OPCODE_TARGETS.fetch(KFN_TECH_TYPE.match?(tech_type.to_s) ? :kfn : :other)
          ranges[opcode_subtype(zone, state)]&.to_a || [opcode_target(zone, state)]
        end

        # @param zone [Zone]
        # @param state [State]
        # @return [Integer] the zone's +TargetTemperature+ in whole °C, rounded half away from zero as the app shows it
        def opcode_target(zone, state) = state.raw['TargetTemperature'].to_a[zone.number - 1].to_i.fdiv(100).round

        # GetWineCoolingZoneSubType gives no subtype past the first zone of a unit of four zones or more.
        #
        # @param zone [Zone]
        # @param state [State]
        # @return [Symbol] +:fridge+, +:freezer+, +:wine+ or +:none+
        def opcode_subtype(zone, state)
          return zone.type if %i[fridge freezer].include?(zone.type)

          (32..34).cover?(identity.device_type) && (zone.number == 1 || opcode_zone_count(state) <= 3) ? :wine : :none
        end
      end
    end
  end
end
