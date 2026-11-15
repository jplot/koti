# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The zone and mode actions of the app's refrigeration module. The app checks nothing before them but the
      # protocol and the kind of appliance, and reads no +RemoteEnable+; {Screen} tells which controls it shows.
      module Commands
        # +ProcessAction+ on and off for an Opcode fridge and freezer zone; the app sends 0 for any other.
        SUPER_MODE_ACTIONS = { fridge: [6, 7], freezer: [4, 5] }.freeze
        private_constant :SUPER_MODE_ACTIONS

        # An Opcode appliance takes its target through +Oc85+, as 16-bit two's complement of whole °C; the Cooling
        # API in hundredths. As the app's ChangeTargetTemperatureAsync, nothing goes out for the zone's current target.
        # SetTargetTemperatureForOpCodeAction posts again 5 s after a 5xx or a lost connection, within 15 s.
        #
        # @param zone [Zone] one of {#zones}
        # @param degrees [Numeric] in {#temperature_unit}, such as one of {#target_choices}; the Cooling API takes
        #   hundredths, rounded to the nearest
        # @return [void]
        # @raise [ArgumentError] on Opcode, for a fraction of a degree or a value out of 16 bits
        # @raise [ResponseError, ConnectionError] on Opcode, a 4xx or a timeout at once, another refusal at the third
        # @api public
        def set_target(zone, degrees)
          whole = whole_degrees(degrees) if opcode?
          return unless new_target?(zone, degrees, state)
          return put('Cooling', "#{zone.number}/TargetTemp", Value: (degrees * 100).round) unless whole

          body = JSON.generate(Request: "10000617000#{zone.number}00#{format('%04X', whole & 0xFFFF)}")
          resent(retries: 3, delay: 5, within: 15) { send_request(:post, "/Devices/#{fab}/Oc85/", body:) }
        end

        # On protocol 201 the app first sets the duration to 720, whatever that write answers, and waits 500 ms.
        #
        # @param zone [Zone] one of {#zones}
        # @param on [Boolean]
        # @return [void]
        # @api public
        def set_super_mode(zone, on)
          return put('State', 'ProcessAction', ProcessAction: process_action(zone, on)) if opcode?

          write_super_mode_duration(zone) if protocol_version == 201
          put('Cooling', "#{zone.number}/SuperMode", **switch(on))
        end

        # @param zone [Zone] one of {#zones}
        # @return [Boolean] whether the app offers {#set_super_mode}: a zone with a super mode, the appliance not
        #   shown off (Status 1, 10 or 255)
        # @api public
        def super_mode_offered?(zone) = !zone.super_mode.nil? && !shown_off?(state)

        # The app shows it for a zone with a fan while {Screen#zones_shown? it shows the zones}.
        #
        # @param zone [Zone] one of {#zones}
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode appliance, which has no Cooling resource
        # @api public
        def set_fan(zone, on)
          write_cooling("#{zone.position}/Fan", **switch(on))
        end

        # The app shows it for a zone with VarioCool while {Screen#zones_shown? it shows the zones}.
        #
        # @param zone [Zone] one of {#zones}
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode appliance, which has no Cooling resource
        # @api public
        def set_vario_cool(zone, on)
          write_cooling("#{zone.rank}/VarioCool", Value: on ? 1 : 2)
        end

        # The app sets a mode {#modes} lists as editable. It goes out once: SetApplianceModeForCoolingApiAction's 5 s
        # Timeout leaves no room for the retry it makes 5 s after a 5xx.
        #
        # @param name [Symbol] +:eco+, +:party+, +:holiday+, +:sabbath+ or +:child_proof+
        # @param on [Boolean]
        # @return [void]
        # @raise [KeyError] for another name
        # @raise [ActionUnavailableError] on an Opcode appliance, which has no Cooling resource
        # @api public
        def set_mode(name, on)
          within(5) { write_cooling(MODES.fetch(name), Value: on ? 1 : 2) }
        end

        private

        # @param resource [String] +Cooling+ or +State+
        # @param member [String] what follows it in the path
        # @param body [Hash{Symbol=>Object}]
        # @return [void]
        def put(resource, member, **body)
          send_request(:put, "/Devices/#{fab}/#{resource}/#{member}", body: JSON.generate(body))
        end

        # @param member [String] what follows +Cooling+ in the path
        # @param body [Hash{Symbol=>Object}]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode appliance
        def write_cooling(member, **body)
          require!(cooling_api?, 'an Opcode appliance has no Cooling resource to write')
          put('Cooling', member, **body)
        end

        # @param degrees [Integer, Float]
        # @return [Integer] as Oc85 carries it, in 16 bits
        # @raise [ArgumentError] for a fraction of a degree or a value out of 16 bits
        def whole_degrees(degrees)
          whole = degrees.to_i
          return whole if whole == degrees && (-0x8000...0x8000).cover?(whole)

          raise ArgumentError, "Oc85 carries whole degrees in 16 bits, not #{degrees}"
        end

        # @param on [Boolean]
        # @return [Hash{Symbol=>Object}]
        def switch(on) = { Value: on ? 1 : 2, SetValues: [1, 2] }

        # @param zone [Zone]
        # @return [void]
        def write_super_mode_duration(zone)
          put('Cooling', "#{zone.number}/SuperModeDuration", Value: 720)
        rescue Error
          nil
        ensure
          @sleeper.call(0.5)
        end

        # @param zone [Zone]
        # @param on [Boolean]
        # @return [Integer]
        def process_action(zone, on) = SUPER_MODE_ACTIONS.fetch(zone.type, [0, 0])[on ? 0 : 1]
      end
    end
  end
end
