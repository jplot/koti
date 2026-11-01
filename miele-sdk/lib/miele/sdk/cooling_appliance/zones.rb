# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The zones as the app's refrigeration module reads them: +Cooling/{n}+ on protocols 200, 201 and 203, the
      # +Temperature+ and +TargetTemperature+ arrays of +State+ on Opcode.
      module Zones
        TYPES = { 19 => :fridge, 20 => :freezer, 32 => :wine_cabinet, 33 => :wine_conditioning,
                  34 => :wine_storage_conditioning, 38 => :cellar, 69 => :biofresh, 76 => :vario_cool }.freeze
        OPCODE_TYPES = { 19 => :fridge, 20 => :freezer, 32 => :wine_cabinet, 33 => :wine_conditioning,
                         34 => :wine_storage_conditioning }.freeze
        # The fridge's and the freezer's super mode in each Opcode Status that shows one.
        OPCODE_SUPER_MODES = { 5 => [false, false], 13 => [false, true], 14 => [true, false],
                               146 => [true, true] }.freeze
        OFF = -32_767
        ABSENT = -32_768
        private_constant :TYPES, :OPCODE_TYPES, :OPCODE_SUPER_MODES, :OFF, :ABSENT

        # @return [Array<Zone>] none while the appliance is off (Status 1 or 255), as the app reads them; a
        #   Cooling API appliance's ranked by position
        # @api public
        def zones
          state = self.state
          return [] unless on?(state)

          opcode? ? opcode_zones(state) : api_zones
        end

        private

        # Status 8 stays allowed: the app hides the zones in a failure only without a failure alarm, which the SDK
        # does not read.
        #
        # @param state [State]
        # @return [void]
        # @raise [ActionUnavailableError] while the app hides the zones: off, or under its Holiday or Sabbath banner
        def require_zones_shown!(state = self.state)
          require!(!shown_off?(state) && !holiday_banner?(state), 'the app shows no zone now')
        end

        # @param state [State]
        # @return [Boolean] Status 1, 10 or 255, which the app shows as off or not connected
        def shown_off?(state) = [1, 10, 255].include?(state.raw['Status'])

        # @param state [State]
        # @return [Boolean] Holiday or Sabbath mode on while on, running or super freezing (Status 2, 5 or 13)
        #   without a door signal
        def holiday_banner?(state)
          door = state.raw['SignalDoor'] == true && !state.raw['SignalFailure'].nil?
          [2, 5, 13].include?(state.raw['Status']) && !door && modes.values_at(:holiday, :sabbath).any? { it&.on }
        end

        # @return [Array<Zone>]
        def api_zones
          listed = cooling
          found = (1..listed['ZoneCounter'].to_i).filter_map { api_zone(it, device("Cooling/#{it}"), listed) }
          found.sort_by(&:position).each_with_index.map { |zone, index| zone.with(rank: index + 1) }
        end

        # The app drops a zone whose temperature reads -32768, except on protocol 200, and shows no temperature
        # there.
        #
        # @param number [Integer]
        # @param zone [Hash{String=>Object}] +Cooling/{number}+
        # @param listed [Hash{String=>Object}] +Cooling+
        # @return [Zone, nil]
        def api_zone(number, zone, listed)
          temperature = zone.dig('Temp', 'Value')
          return if temperature == ABSENT && protocol_version != 200

          state = zone['ZoneState'] || {}
          super_mode, fan, vario_cool = switches(zone, listed)
          Zone.new(number:, position: zone_position(state['Position'], number), rank: nil,
                   type: TYPES.fetch(state['Type'], :unknown), enabled: state['Value'] == 1,
                   temperature: protocol_version == 200 ? nil : degrees(temperature),
                   target: degrees(zone.dig('TargetTemp', 'Value')), super_mode:, fan:, vario_cool:)
        end

        # @param position [Integer, nil] +ZoneState.Position+
        # @param number [Integer]
        # @return [Integer] 1 top, 2 middle, 3 bottom, else the zone's number
        def zone_position(position, number) = [1, 2, 3].include?(position) ? position.to_i : number

        # The app shows the fan only when +PresentationType+ is 3.
        #
        # @param zone [Hash{String=>Object}]
        # @param listed [Hash{String=>Object}]
        # @return [Array(Boolean, Boolean, Boolean)] super mode, fan and VarioCool, each nil when absent
        def switches(zone, listed)
          [zone['SuperMode'] && zone.dig('SuperMode', 'Value') == 1,
           listed['PresentationType'] == 3 && zone['Fan'] ? zone.dig('Fan', 'Value') == 1 : nil,
           zone['VarioCool'] && zone.dig('VarioCool', 'Value') == 1]
        end

        # @param state [State]
        # @return [Array<Zone>]
        def opcode_zones(state)
          temperatures = Array(state.raw['Temperature']) #: Array[Integer?]
          (0...opcode_zone_count(state)).filter_map do |index|
            opcode_zone(index + 1, temperatures[index], Array(state.raw['TargetTemperature'])[index], state)
          end
        end

        # @param state [State]
        # @return [Integer] one or two zones by device type, else as many as the temperatures shown
        def opcode_zone_count(state)
          temperatures = Array(state.raw['Temperature']) #: Array[Integer?]
          { 19 => 1, 20 => 1, 21 => 2 }.fetch(identity.device_type) { temperatures.count { it != ABSENT } }
        end

        # @param number [Integer]
        # @param temperature [Integer, nil] in hundredths of °C
        # @param target [Integer, nil]
        # @param state [State]
        # @return [Zone, nil]
        def opcode_zone(number, temperature, target, state)
          return if temperature == ABSENT

          type = opcode_type(number)
          Zone.new(number:, position: number, rank: number, type:, enabled: temperature != OFF,
                   temperature: degrees(temperature), target: degrees(target),
                   super_mode: opcode_super_mode(state, type), fan: nil, vario_cool: nil)
        end

        # @param number [Integer]
        # @return [Symbol]
        def opcode_type(number)
          return number == 1 ? :fridge : :freezer if identity.device_type == 21

          OPCODE_TYPES.fetch(identity.device_type, :unknown)
        end

        # @param state [State]
        # @param type [Symbol]
        # @return [Boolean, nil]
        def opcode_super_mode(state, type)
          modes = OPCODE_SUPER_MODES[state.raw['Status']]
          return unless modes && %i[fridge freezer].include?(type)

          type == :fridge ? modes[0] : modes[1]
        end

        # @param value [Integer, nil] hundredths of a degree
        # @return [Float, nil] nil for a zone off or without the value
        def degrees(value) = value.nil? || value <= OFF ? nil : value / 100.0
      end
    end
  end
end
