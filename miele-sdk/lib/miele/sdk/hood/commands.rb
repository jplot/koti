# frozen_string_literal: true

module Miele
  module Sdk
    class Hood < Appliance
      # The hood actions the app sends in more than one protocol, each by the route {Wire} picks.
      module Commands
        FAN_LEVELS = (0..5)
        RUN_ON_TIMES = [0, 5, 15].freeze
        FRAGRANCE_SETTINGS = { stop: 0, start: 1, miele_program: 2 }.freeze
        private_constant :FAN_LEVELS, :RUN_ON_TIMES, :FRAGRANCE_SETTINGS

        # @param level [Integer] 0 (off) to 3, 4 (boost) or 5 (interval)
        # @return [void]
        # @raise [ArgumentError] if the level is out of range
        # @raise [ActionUnavailableError] while the hood's screen is pushed in, as the app refuses then
        # @api public
        def fan_level=(level)
          raise ArgumentError, "fan level #{level} is out of 0..5" unless FAN_LEVELS.cover?(level)

          require_reading!(fan_settable?, 'the fan cannot be set while the screen is pushed in')
          case route(:fan)
          when :dop1 then tolerating_no_op { dop1(Dop1.fan_level(level)) }
          when :opcode then opcode_twice("10000608010#{level}000000")
          else write_dop2(hood_select(1 => level))
          end
        end

        # @param minutes [Integer] 0, 5 or 15
        # @return [void]
        # @raise [ArgumentError] for any other duration
        # @api public
        def fan_run_on_time=(minutes)
          raise ArgumentError, "run-on time #{minutes} is not 0, 5 or 15" unless RUN_ON_TIMES.include?(minutes)

          case route(:fan)
          when :dop1 then tolerating_no_op { dop1(Dop1.fan_run_on_time(minutes)) }
          when :opcode then opcode(format('10000609%02X00000000', minutes))
          else write_dop2(hood_select(2 => minutes))
          end
        end

        # @param on [Boolean]
        # @return [void]
        # @api public
        def main_light=(on)
          case route(:fan)
          when :dop1 then tolerating_no_op { dop1(Dop1.main_light(on)) }
          when :opcode then send_request(:put, "/Devices/#{fab}/State/", body: JSON.generate('Light' => on ? '1' : '2'))
          else dop2_user_request(on ? 13 : 14)
          end
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] when the hood has no ambient light, or drives its lights by Opcode, whose
        #   second light the app never switches
        # @api public
        def ambient_light=(on)
          path = route(:fan)
          require!(path != :opcode, 'an Opcode hood has no ambient light the app switches')
          require_reading!(lights&.ambient&.exists, 'the hood has no ambient light')
          request = on ? 20_001 : 20_002
          path == :dop1 ? dop1_ambient_light(on) : dop2_user_request(request)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode hood
        # @api public
        def ambient_light_while_cooking=(on)
          value = on ? 1 : 0
          route(:setting) == :dop1 ? write_setting(40_029, value) : write_sf(9001, value)
        end

        # @return [void]
        # @api public
        def reset_grease_filter = reset_filter(40_012, 20_009, '0B0003000300')

        # @return [void]
        # @api public
        def reset_charcoal_filter = reset_filter(40_013, 20_008, '0B0003000400')

        # @param action [Symbol] +:start+ (20 minutes), +:stop+ or +:miele_program+
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode hood, or when the hood has no fragrance
        # @raise [ArgumentError] for another action
        # @api public
        def fragrance(action)
          value = FRAGRANCE_SETTINGS.fetch(action) { raise ArgumentError, "no fragrance action #{action.inspect}" }
          return dop1_fragrance(action) if route(:setting) == :dop1

          require_reading!(extended&.then { second_functions(it)[5] == 1 }, 'the hood has no fragrance')
          write_sf(9009, value)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode hood, or when the hood has no auto refresh
        # @api public
        def auto_refresh=(on)
          path = route(:setting)
          require_reading!(auto_refresh_supported?, 'the hood has no auto refresh')
          value = on ? 1 : 0
          path == :dop1 ? write_setting(40_023, value) : write_sf(9007, value)
        end

        # @param active [Boolean]
        # @param interval [Integer] 5, 10 or 20 seconds
        # @return [void]
        # @raise [ArgumentError] for another interval
        # @raise [ActionUnavailableError] when the hood has no ColorFlow
        # @api public
        def configure_color_flow(active:, interval: 10)
          raise ArgumentError, "no ColorFlow interval #{interval}" unless COLOR_FLOW_INTERVALS.include?(interval)

          require!(color_flow, 'the hood has no ColorFlow')
          body = JSON.generate('active' => active, 'intervalDurationSeconds' => interval)
          send_request(:put, "/Devices/#{fab}/ColorFlow", body:)
        end

        # Con@ctivity Plus: the hood follows one more hob.
        #
        # @param hob [String] its fabrication number
        # @return [void]
        # @raise [ActionUnavailableError] when the hood does not offer Con@ctivity Plus
        # @api public
        def connect_hob(hob) = update_connectivity_plus { (it + [hob]).uniq }

        # @param hob [String] its fabrication number
        # @return [void]
        # @raise [ActionUnavailableError] when the hood does not offer Con@ctivity Plus
        # @api public
        def disconnect_hob(hob) = update_connectivity_plus { it - [hob] }

        # A Dop1 or Opcode hood wakes when its State is written back, the light as it is; DOP2 takes
        # +DeviceAction+ 2 (DefaultWakeUpAction).
        #
        # @return [void]
        # @api public
        def wake
          return super if [3, 4].include?(protocol_version)

          state = self.state
          command(Schema::DeviceState.new(light: state.raw['Light'])) if state.status == :off
        end

        private

        # The app changes one hob in the list +services+ shows and derives +activated+ from what is left
        # (UpdateConactivityPlusSettingsHelper).
        #
        # @yieldparam sources [Array<String>] the hobs followed
        # @yieldreturn [Array<String>] those to follow
        # @return [void]
        # @raise [ActionUnavailableError] when the hood does not offer Con@ctivity Plus
        def update_connectivity_plus
          plus = connectivity_plus
          require!(plus&.available, 'the hood offers no Con@ctivity Plus')
          sources = yield Array(plus&.sources)
          body = JSON.generate('activated' => sources.any?, 'sourceDeviceIds' => sources)
          send_request(:put, "/Devices/#{fab}/services/ConnectivityPlus", body:)
        end

        # The hood serves +ExtendedState+, and so what it supports, only while it is on.
        #
        # @param value [Boolean, nil] read from +ExtendedState+, nil when it serves none
        # @param reason [String] why the hood refuses when the value is false
        # @return [void]
        # @raise [ActionUnavailableError]
        def require_reading!(value, reason)
          require!(!value.nil?, 'the hood is off and serves no ExtendedState: wake it first')
          require!(value, reason)
        end

        # @param pf_id [Integer] its Dop1 setting
        # @param request [Integer] its DOP2 user request
        # @param opcode_request [String] its Oc85 request
        # @return [void]
        def reset_filter(pf_id, request, opcode_request)
          case route(:filter)
          when :dop1 then write_setting(pf_id, 1)
          when :opcode then opcode(opcode_request)
          else dop2_user_request(request)
          end
        end
      end
    end
  end
end
