# frozen_string_literal: true

module Miele
  module Sdk
    module Schema
      # What an appliance is doing, from its +State+, and the body of a command written there (Miele app
      # class +DeviceStateDto+, which the app writes with +DeviceAction+, +ProcessAction+, +Light+ or
      # +StartTime+ alone).
      #
      # @!attribute [r] status
      #   @return [Integer, nil] named by {Catalog::STATUS}
      # @!attribute [r] internal_state
      #   @return [Integer, nil]
      # @!attribute [r] program_type
      #   @return [Integer, nil]
      # @!attribute [r] program_id
      #   @return [Integer, nil]
      # @!attribute [r] program_phase
      #   @return [Integer, nil]
      # @!attribute [r] remaining_time
      #   @return [Array<Integer>, nil] hours and minutes
      # @!attribute [r] start_time
      #   @return [Array<Integer>, nil] hours and minutes
      # @!attribute [r] target_temperature
      #   @return [Array<Integer>, nil] hundredths of a degree, -32768 where none is set
      # @!attribute [r] temperature
      #   @return [Array<Integer>, nil] hundredths of a degree, -32768 where nothing is measured
      # @!attribute [r] signal_info
      #   @return [Boolean, nil]
      # @!attribute [r] signal_failure
      #   @return [Boolean, nil]
      # @!attribute [r] signal_door
      #   @return [Boolean, nil]
      # @!attribute [r] remote_enable
      #   @return [Array<Integer>, nil]
      # @!attribute [r] process_action
      #   @return [Integer, nil] written 1 to start, 2 to stop, 3 to pause
      # @!attribute [r] light
      #   @return [Integer, nil] 1 on, 2 off
      # @!attribute [r] extended_state
      #   @return [String, nil]
      # @!attribute [r] ventilation_step
      #   @return [Integer, nil]
      # @!attribute [r] elapsed_time
      #   @return [Array<Integer>, nil] hours and minutes
      # @!attribute [r] device_action
      #   @return [Integer, nil] written 2 to wake the appliance
      # @!attribute [r] standby_state
      #   @return [Integer, nil]
      # @!attribute [r] sync_state
      #   @return [Integer, nil]
      # @!attribute [r] plate_step
      #   @return [Array<Integer>, nil]
      # @!attribute [r] plate_remaining_heat
      #   @return [Array<Integer>, nil]
      # @!attribute [r] plate_remaining_minutes
      #   @return [Array<Integer>, nil]
      # @!attribute [r] plate_elapsed_minutes
      #   @return [Array<Integer>, nil]
      # @!attribute [r] plate_timer_seconds
      #   @return [Array<Integer>, nil]
      # @!attribute [r] spinning_speed
      #   @return [Integer, nil]
      # @!attribute [r] drying_step
      #   @return [Integer, nil]
      DeviceState = Data.define(:status, :internal_state, :program_type, :program_id, :program_phase,
                                :remaining_time, :start_time, :target_temperature, :temperature, :signal_info,
                                :signal_failure, :signal_door, :remote_enable, :process_action, :light,
                                :extended_state, :ventilation_step, :elapsed_time, :device_action, :standby_state,
                                :sync_state, :plate_step, :plate_remaining_heat, :plate_remaining_minutes,
                                :plate_elapsed_minutes, :plate_timer_seconds, :spinning_speed, :drying_step) do
        include Value

        optional(*members)
        keys program_id: 'ProgramID'
      end
    end
  end
end
