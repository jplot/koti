# frozen_string_literal: true

module Miele
  module Sdk
    # A warming drawer, which the Miele app's drawer module handles (device type 25, Dop1).
    class WarmingDrawer < Appliance
      include Commands

      # A program as the drawer's 9788 describes it.
      #
      # @!attribute [r] id
      #   @return [Integer] 1 cups, 2 plates, 3 food, 4 low-temperature cooking
      # @!attribute [r] min_hours
      #   @return [Integer]
      # @!attribute [r] max_hours
      #   @return [Integer]
      # @!attribute [r] temperatures
      #   @return [Array<Integer>] the five °C steps the app offers
      Program = Data.define(:id, :min_hours, :max_hours, :temperatures)

      STATES = { 1 => :off, 2 => :on, 3 => :programmed, 4 => :waiting_to_start, 5 => :running, 6 => :paused,
                 7 => :finished, 8 => :fault, 9 => :cancelled, 10 => :idle, 12 => :settings, 144 => :default,
                 145 => :locked, 255 => :not_connected }.freeze
      SECTIONS = %i[tassenwaermen tellerwaermen speisenwaermen nt_garen].freeze
      private_constant :STATES, :SECTIONS

      # The app's drawer state: an open door shows over off, on, running and paused, and a program chosen
      # turns on into programmed.
      #
      # @param state [State]
      # @return [Symbol] +:off+, +:off_and_door_open+, +:on+, +:programmed+, +:running+, +:door_open+…, +:unknown+
      # @api public
      def drawer_state(state = self.state)
        status = state.raw['Status']
        door = state.raw['SignalDoor'] == true && [1, 2, 5, 6].include?(status)
        return status == 1 ? :off_and_door_open : :door_open if door
        return :programmed if status == 2 && state.raw['ProgramID'].to_i.positive?

        STATES.fetch(status, :unknown)
      end

      # @return [Array<Program>] programs 1 to 4, read from 9788
      # @api public
      def programs
        settings = dop1_object(Objects::Drawer::ServiceExtEswSettings)
        SECTIONS.each_with_index.map do |name, index|
          section = settings.public_send(name)
          Program.new(id: index + 1, min_hours: section.minimale_laufzeit, max_hours: section.maximale_laufzeit,
                      temperatures: (0..4).map { section.public_send(:"temperatur_stufe#{it}") })
        end
      end

      # @return [Hash{String=>Object}, nil] +services+' +CupsWarmUp+: +available+, +activated+,
      #   +availableSourceDeviceIDs+, +sourceDeviceId+
      # @api public
      def cups_warm_up = services['CupsWarmUp']
    end
  end
end
