# frozen_string_literal: true

module Miele
  module Sdk
    class WarmingDrawer < Appliance
      # The actions of the app's drawer module: Dop1 writes on 1101 and 9781, which raise {NotAcceptedError} on an
      # Ack other than 1, and the cup warm-up in +services+. The predicates give the rule the app enables each by.
      module Commands
        # @return [void]
        # @api public
        def power_on = write_device_action(2)

        # The app's settings switch shows off, and so offers on, in these states only.
        #
        # @return [Boolean] whether the app offers {#power_on}: {#switchable?}, and off, off with the door open,
        #   finished or idle
        # @api public
        def power_on_offered?
          state = self.state
          switchable?(state) && %i[off off_and_door_open finished idle].include?(drawer_state(state))
        end

        # @return [void]
        # @api public
        def power_off = write_device_action(3)

        # The app's settings switch, action bar and dashboard each allow it; the SDK tells when any of them does.
        #
        # @return [Boolean] whether the app offers {#power_off}: {#switchable?}, and neither off, off with the door
        #   open, finished nor not connected
        # @api public
        def power_off_offered?
          state = self.state
          switchable?(state) && !%i[off off_and_door_open finished not_connected].include?(drawer_state(state))
        end

        # @param id [Integer] 1 cups, 2 plates, 3 food, 4 low-temperature cooking
        # @return [void]
        # @raise [ArgumentError] for another program, which +Betriebsart+ does not define
        # @api public
        def select_program(id)
          raise ArgumentError, 'the drawer runs programs 1 to 4' unless (1..4).cover?(id)

          write_process_data(id, 0, 0)
        end

        # @return [Boolean] whether the app offers {#select_program}: under remote control and mobile start without
        #   local control, the drawer on, running or off
        # @api public
        def select_program_offered?
          state = self.state
          controllable?(state) && %i[on running off off_and_door_open].include?(drawer_state(state))
        end

        # The app re-sends the remaining time +State+ shows.
        #
        # @param celsius [Integer] such as one of the program's temperatures, which {#programs} gives
        # @return [void]
        # @raise [ArgumentError] for degrees a byte does not hold
        # @api public
        def target_temperature=(celsius)
          raise ArgumentError, "#{celsius} °C does not fit the temperature's byte" unless (0..255).cover?(celsius)

          state = self.state
          write_process_data(state.raw['ProgramID'].to_i, remaining_minutes(state), celsius)
        end

        # @return [Boolean] whether the app sets the temperature: {#switchable?}, with a program
        # @api public
        def target_temperature_offered?
          state = self.state
          switchable?(state) && !program(state).nil?
        end

        # The app keeps the time to the program's maximum hours, 0 without a program, and re-sends the target
        # temperature +State+ shows; 0 resets it. {#programs} gives the minimum hours its picker offers past 0.
        #
        # @param minutes [Integer]
        # @return [void]
        # @raise [ArgumentError] for a negative time
        # @api public
        def remaining_time=(minutes)
          raise ArgumentError, "a remaining time of #{minutes} min is negative" if minutes.negative?

          state = self.state
          minutes = [minutes, program(state)&.max_hours.to_i * 60].min
          write_process_data(state.raw['ProgramID'].to_i, minutes, target_celsius(state))
        end

        # @return [Boolean] whether the app sets the remaining time: under remote control and mobile start without
        #   local control, the program set or running (Status 3 to 6)
        # @api public
        def remaining_time_offered?
          state = self.state
          controllable?(state) && [3, 4, 5, 6].include?(state.raw['Status'])
        end

        # @param coffee_maker [String, nil] the fab of a coffee maker, such as one {#cups_warm_up} lists, nil to stop
        # @return [void]
        # @api public
        def cups_warm_up_source=(coffee_maker)
          body = coffee_maker ? { activated: true, sourceDeviceId: coffee_maker } : { activated: false }
          send_request(:put, "/Devices/#{fab}/services/CupsWarmUp", body: JSON.generate(body))
        end

        # @return [Boolean] whether the app offers the cup warm-up: the drawer connected and {#cups_warm_up}
        #   available
        # @api public
        def cups_warm_up_offered? = state.raw['Status'] != 255 && cups_warm_up.to_h['available'] == true

        # @param state [State] read when not given
        # @return [Boolean] mobile start without local control, which every switch and setting of the app needs
        # @api public
        def switchable?(state = self.state) = state.mobile_start? == true && state.local_control? != true

        private

        # @param state [State]
        # @return [Boolean] remote control and mobile start without local control
        def controllable?(state) = switchable?(state) && state.remote_control? == true

        # @param action [Integer] 2 on, 3 off
        # @return [void]
        def write_device_action(action)
          section = blank(Objects::Drawer::DeviceAction::DeviceActionWriteSection).with(struktur_version: 1, action:)
          write_dop1_object(Objects::Drawer::DeviceAction, section, type: Dop1::WRITE)
        end

        # The app writes the hours of the time left without its days.
        #
        # @param program [Integer]
        # @param minutes [Integer]
        # @param celsius [Integer]
        # @return [void]
        def write_process_data(program, minutes, celsius)
          section = blank(Objects::Drawer::ServiceExtEswProcessData::ServiceExtEswProcessDataWriteSection)
                    .with(struktur_version: 1, betriebsart: program, restzeit_minuten: minutes % 60,
                          restzeit_stunden: minutes / 60 % 24, prozess_temperatur: celsius)
          write_dop1_object(Objects::Drawer::ServiceExtEswProcessData, section, type: Dop1::WRITE)
        end

        # @param state [State]
        # @return [Program, nil] the program +State+ shows
        def program(state) = programs.find { it.id == state.raw['ProgramID'] }

        # @param state [State]
        # @return [Integer] +RemainingTime+ [h, m] in minutes, 0 without both
        def remaining_minutes(state)
          hours, minutes = state.raw['RemainingTime']
          hours && minutes ? (hours * 60) + minutes : 0
        end

        # @param state [State]
        # @return [Integer] whole °C, 255 outside 0 to 100 as the app sends it
        def target_celsius(state)
          celsius = (state.raw['TargetTemperature']&.first.to_i / 100.0).truncate
          state.raw['TargetTemperature'] && (0..100).cover?(celsius) ? celsius : 255
        end
      end
    end
  end
end
