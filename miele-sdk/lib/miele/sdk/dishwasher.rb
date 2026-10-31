# frozen_string_literal: true

module Miele
  module Sdk
    # A dishwasher, which the Miele app's dishwasher module handles (device types 7, and 8 on PG81 models).
    class Dishwasher < Appliance
      include Rules
      include Commands
      include Dop1Commands
      include Power

      # What a Dop1 dishwasher uses now.
      #
      # @!attribute [r] energy
      #   @return [Float] divided by 10, as the app shows it
      # @!attribute [r] water
      #   @return [Float] divided by 10, as the app shows it
      Consumption = Data.define(:energy, :water)

      REQUESTS = { 1 => :start, 2 => :stop, 3 => :pause, 8 => :start_delay, 52 => :cancel }.freeze
      DOP1_REQUESTS = { 3 => %i[start], 4 => %i[start cancel], 5 => %i[pause stop] }.freeze
      private_constant :REQUESTS, :DOP1_REQUESTS

      # @return [Objects::Dishwasher::GlobalDeviceContext] 2/1585, idx 0/1
      # @api public
      def context = object(Objects::Dishwasher::GlobalDeviceContext)

      # @return [Objects::Dishwasher::GlobalPsContext] 2/1574, idx 0/1
      # @api public
      def program_context = object(Objects::Dishwasher::GlobalPsContext)

      # @return [Objects::Dishwasher::GlobalProgramList] 2/1584, idx 0/1
      # @api public
      def programs = object(Objects::Dishwasher::GlobalProgramList)

      # @return [Objects::Dishwasher::GlobalNtfctnShow] 2/131, idx 0/1
      # @api public
      def notifications = object(Objects::Dishwasher::GlobalNtfctnShow)

      # @param id [Integer] a +GLOBAL_EnumSfId+ value, such as 20052 for AutoDos
      # @return [Objects::Dishwasher::GlobalSfValue] 2/105, at idx1 the id and idx2 1
      # @api public
      def setting(id) = object(Objects::Dishwasher::GlobalSfValue, [2, 105, id, 1])

      # @return [Boolean] +RemoteEnable+ 7, which only a DOP2 dishwasher reports
      # @api public
      def locked? = locked_in?(state)

      # @return [Boolean] +AppSupport+ bit 4 on a DOP2 dishwasher; a Dop1 one always has it
      # @api public
      def mobile_control? = !dop2? || identity.app_support.to_i[4] == 1

      # A Dop1 dishwasher tells them by its +Status+; a PG81 offers none.
      #
      # @return [Array<Symbol>] +:start+, +:stop+, +:pause+, +:start_delay+ or +:cancel+
      # @api public
      def supported_requests
        if dop2?
          Array(context.supported_user_requests).filter_map { REQUESTS[Objects::Dishwasher::GlobalEnumUserRequestId.to_i(it)] }
        elsif pg81?
          []
        else
          DOP1_REQUESTS.fetch(state.raw['Status'], %i[start stop])
        end
      end

      # @return [Data] Dop1 object 8905
      # @api public
      def program_list = dop1_object(Objects::Dishwasher::SmartControlGsdProgrammliste)

      # @return [Data] Dop1 object 8907: the extras, duration and forecast of the selected program
      # @api public
      def selection = dop1_object(Objects::Dishwasher::SmartControlGsdProgrammwahlLesen)

      # The app reads it from +ExtendedState+ past its first 3 bytes, u16 at 12 and 14 (DeviceState 1000).
      #
      # @return [Consumption, nil] nil on a DOP2 or PG81 dishwasher, or without +ExtendedState+
      # @api public
      def consumption
        return if dop2? || pg81?

        bytes = [state.raw['ExtendedState'].to_s].pack('H*').byteslice(3..).to_s
        return if bytes.bytesize < 16

        energy, water = bytes.unpack('@12nn')
        Consumption.new(energy: tenths(energy), water: tenths(water))
      end

      # @return [Hash{String=>Object}] the detergent trays, as served
      # @api public
      def consumables = device('Consumables')

      # @return [Hash{String=>Object}, nil] runs and consumption by week, month and year; the app reads them on
      #   DOP2 only
      # @api public
      def statistics = (device('Statistics') if dop2?)

      # @return [Hash{String=>Object}, nil] DOP2 only, as in the app
      # @api public
      def latest_program_runs = (device('LatestProgramRuns') if dop2?)

      private

      # @return [Boolean]
      def dop2? = [3, 4].include?(protocol_version)

      # @return [Boolean]
      def pg81? = tech_type.to_s.start_with?('PG81')

      # @param value [Integer, nil]
      # @return [Float] divided by 10 and rounded to a tenth, as the app does
      def tenths(value) = (value.to_i / 10.0).round(1).to_f

      # @param klass [Class] a generated Dop1 object
      # @return [Data] read with an empty section, as the app reads it
      def dop1_object(klass)
        answer = JSON.parse(dop1(Dop1.request(object_id: klass::ID, type: Dop1::READ, section: ''))).fetch('Response')
        klass.from([answer[8..]].pack('H*'))
      end
    end
  end
end
