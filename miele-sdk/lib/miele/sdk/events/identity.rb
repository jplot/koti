# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    module Events
      # What this host answers when an appliance probes it before pushing to
      # it, shaped like ha-miele-at-lan's answers, which appliances accept.
      module Identity
        STATE = {
          Status: 1, InternalState: 0, ProgramType: 0, ProgramID: 0, ProgramPhase: 0, RemainingTime: [0, 0],
          StartTime: [0, 0], TargetTemperature: [-32_768] * 3, Temperature: [-32_768] * 3, SignalInfo: false,
          SignalFailure: false, SignalDoor: false, RemoteEnable: [15, 1, 1], ProcessAction: 0, DeviceAction: 0,
          Light: 2, StandbyState: 1, ElapsedTime: [0, 0], SyncState: 1
        }.freeze
        private_constant :STATE

        module_function

        # @param path [String] path of a GET request
        # @param fab [String] fabrication number this host takes
        # @return [Array(Integer, String), Array(Integer)] status and JSON body, or 204 for any other path
        # @api private
        def resource(path, fab)
          body = routes(fab).find { |pattern, _| pattern.match?(path.delete_suffix('/')) }&.last
          body ? [200, JSON.generate(body)] : [204]
        end

        # @param fab [String]
        # @return [Hash{Regexp=>Hash}] answer by path, trailing slash removed
        # @api private
        def routes(fab)
          { %r{\A/Devices\z} => { fab => { href: "#{fab}/", Group: Sdk.config.group_id, Pairing: false } },
            %r{\A/Devices/\d+\z} => %w[DOP2 Ident State Settings SuperVision].to_h { [it, { href: "#{it}/" }] },
            %r{\A/Devices/\d+/Ident\z} => ident(fab), %r{\A/Devices/\d+/State\z} => STATE,
            %r{\A/Devices/\d+/SuperVision\z} => { Enabled: true, ErrorOnly: false },
            %r{\A/Devices/\d+/SuperVision/\d+\z} => { Show: true, Signal: true } }
        end

        # @param fab [String]
        # @return [Hash{Symbol=>Object}]
        # @api private
        def ident(fab)
          { DeviceType: DEVICE_TYPE, SubType: 0, DeviceName: 'koti', AppSupport: 661, FctSupport: 7, XKMSupport: 7,
            ProtocolVersion: 4,
            DeviceIdentLabel: { Version: 'E', FabNumber: fab, FabIndex: '01', TechType: 'KOTI', MatNumber: '00000001',
                                SWIDs: [1] },
            XKMIdentLabel: { Version: 'E', FabNumber: '000000000001', FabIndex: '00', TechType: 'EK057S',
                             MatNumber: '00000000', SWIDs: [1], ReleaseVersion: '09.14' } }
        end
      end
    end
  end
end
