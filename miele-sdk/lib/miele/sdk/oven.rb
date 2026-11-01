# frozen_string_literal: true

module Miele
  module Sdk
    # An oven, steam oven or oven with microwave, which the Miele app's oven module handles (device types 12, 13,
    # 15, 31, 39 and 45).
    class Oven < Appliance
      include ProgramSelection
      include Selection
      include Requests
      include SteamBurst
      include OvenState

      NOTIFICATION_IDS = { info: Objects::Oven::GlobalEnumNtfctnInfoId, message: Objects::Oven::GlobalEnumNtfctnMessageId,
                           query: Objects::Oven::GlobalEnumNtfctnQueryId }.freeze
      private_constant :NOTIFICATION_IDS

      # Switches the appliance on as the app's oven module does, waking it first when it sleeps. The app's
      # other families switch on in their own way.
      #
      # @return [void]
      # @raise [ActionUnavailableError] on a Dop1 or H2 oven, or without remote control or mobile start
      # @raise [ResponseError] if the appliance still refuses after three attempts
      # @api public
      def power_on
        require_switch_on!
        3.times do |attempt|
          rouse if attempt.positive?
          return write_dop2(power_leaf(4))
        rescue ResponseError => e
          raise unless e.status == 500 && attempt < 2
        end
      end

      # The app's SendSwitchOffAsync swallows a 500 on its write.
      #
      # @return [void]
      # @raise [ActionUnavailableError] on a Dop1 oven, or without remote control or mobile start, or under local
      #   control, or not connected
      # @raise [ResponseError] if the appliance refuses with another status
      # @api public
      def power_off
        require_switch_off!
        begin
          write_dop2(power_leaf(1))
        rescue ResponseError => e
          raise unless e.status == 500
        end
      end

      # @return [Objects::Oven::GlobalDeviceContext] 1/1585, read without an index as the app observes it
      # @api public
      def context = object(Objects::Oven::GlobalDeviceContext)

      # @return [Objects::Oven::GlobalPsContext] 1/1574: the selected program and its parameters
      # @api public
      def program_context = object(Objects::Oven::GlobalPsContext)

      # @param second_cavity [Boolean] a double oven's second cavity, read on 1/392
      # @return [Objects::Oven::GlobalNtfctnShow] 1/131: infos, messages, errors and queries
      # @api public
      def notifications(second_cavity: false)
        klass = Objects::Oven::GlobalNtfctnShow
        object(klass, klass::ADDRESSES.fetch(second_cavity ? 1 : 0))
      end

      # @return [Objects::Oven::GlobalProgramGroupsComplete] 1/1599: the programs the oven offers
      # @api public
      def program_groups = object(Objects::Oven::GlobalProgramGroupsComplete)

      # The app reads them along a chain: each instance gives the next one's idx1 as its idx2, the last its own.
      #
      # @return [Array<Objects::Oven::GlobalOpProgramName>] the own programs, from 1/109
      # @api public
      def own_programs
        programs = [] #: Array[untyped]
        idx1 = 0
        loop do
          leaf = dop2(1, 109, idx1:, idx2: 1)
          programs << Objects::Oven::GlobalOpProgramName.from(leaf.fields)
          return programs if leaf.idx1 == leaf.idx2

          idx1 = leaf.idx2
        end
      end

      # @return [Array(Objects::Oven::GlobalOpProgramInfoCA, Array<Objects::Oven::GlobalOpProgramStepInfoCA>)] the
      #   running own program (2/213) and its steps (2/214, idx1 0 on)
      # @api public
      def program_steps
        info = object(Objects::Oven::GlobalOpProgramInfoCA)
        step = Objects::Oven::GlobalOpProgramStepInfoCA
        [info, Array.new(info.amount_of_steps.to_i) { object(step, [2, 214, it, 1]) }]
      end

      # @return [Objects::Oven::GlobalDeviceContext2ndDevice] 1/391: a double oven's second cavity
      # @api public
      def second_cavity_context = object(Objects::Oven::GlobalDeviceContext2ndDevice)

      # @return [Float, nil] °C, nil when no program sets it
      # @api public
      def target_temperature = celsius(:temperature)

      # @return [Float, nil] °C of the core probe, nil when no program sets it
      # @api public
      def core_target_temperature = celsius(:core_temperature)

      # @param type [Symbol] +:info+, +:message+, +:error+ or +:query+, as {#notifications} lists them
      # @param id [Integer, Symbol] the notification's id
      # @param option [Integer, Symbol] one of its +ack_options+, a value of +GLOBAL_EnumNTFCTNAckOptions+
      # @param second_cavity [Boolean] a double oven's second cavity, answered on 5/138
      # @return [void]
      # @raise [ActionUnavailableError] on a Dop1 oven
      # @api public
      def acknowledge(type, id, option:, second_cavity: false)
        require_dop2!
        id = NOTIFICATION_IDS[type]&.to_i(id) || id
        option = Objects::Oven::GlobalEnumNTFCTNAckOptions.to_i(option)
        write_dop2(Messages.acknowledge(second_cavity ? 5 : 2, type, id, option))
      end

      # @return [Array<Integer>] the user requests the oven offers now, numbered as the app numbers them
      # @api public
      def supported_requests = offered(context)

      private

      # @param state [State]
      # @return [Boolean] remote control without local control
      def under_remote_control?(state = self.state) = state.remote_control? && !state.local_control?

      # @return [Boolean]
      def dop2? = [3, 4].include?(protocol_version)

      # @return [void]
      # @raise [ActionUnavailableError] on a Dop1 oven, which the app only stops
      def require_dop2! = require!(dop2?, 'a Dop1 oven only stops, as in the app')

      # @param context [Objects::Oven::GlobalDeviceContext] 1/1585
      # @return [Array<Integer>]
      def offered(context)
        Array(context.supported_user_requests).map { Objects::Oven::GlobalEnumUserRequestId.to_i(it) }
      end

      # @param parameter [Symbol] a member of +GLOBAL_PS_ContextParaCA+, in hundredths of °C
      # @return [Float, nil]
      def celsius(parameter)
        value = program_context.context_para_ca&.public_send(parameter)
        value&.current_value&.then { it / 100.0 }
      end

      # IsDiscoveryOven, and the app's offline screen, the loosest of its switch-on paths.
      #
      # @return [void]
      # @raise [ActionUnavailableError]
      def require_switch_on!
        require_dop2!
        require!(!tech_type.to_s.start_with?('H2'), 'the app does not switch on an H2 oven')
        state = self.state
        require!(state.remote_control? || state.mobile_start?, 'the oven is not remote enabled')
      end

      # UpdateEnabledState of the app's settings switch, the loosest of its three switch-off paths.
      #
      # @return [void]
      # @raise [ActionUnavailableError]
      def require_switch_off!
        require_dop2!
        state = self.state
        require!(under_remote_control?(state) || (!state.remote_control? && state.mobile_start?),
                 'the oven is not remote enabled, or is under local control')
        require!(state.status != :not_connected, 'the oven is not connected')
      end

      # The appliance state on 2/1586: 4 switches on, 1 off.
      #
      # @param state [Integer]
      # @return [Dop2::Leaf]
      def power_leaf(state)
        Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                       fields: { 1 => Dop2::Field.new(type: :e8, value: state) })
      end

      # A sleeping appliance answers 500 to the state write; the app then sends DeviceAction 2, waits 3 s and
      # tries again, with no limit: three attempts here.
      #
      # @return [void]
      def rouse
        begin
          wake
        rescue ResponseError
          nil
        end
        @sleeper.call(3)
      end
    end
  end
end
