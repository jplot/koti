# frozen_string_literal: true

module Miele
  module Sdk
    class Hood < Appliance
      # How the app's hood module reaches each protocol. Its action lists take the first action that supports the
      # hood (SelectBestAction), so a protocol 3 hood drives its fan and lights as an Opcode one.
      module Wire
        ROUTES = {
          fan: { 1 => :opcode, 2 => :dop1, 3 => :opcode, 4 => :dop2 },
          filter: { 1 => :opcode, 2 => :dop1, 3 => :dop2, 4 => :dop2 },
          setting: { 2 => :dop1, 3 => :dop2, 4 => :dop2 }
        }.freeze
        private_constant :ROUTES

        private

        # @param kind [Symbol] +:fan+ (also the run-on and the lights), +:filter+ or +:setting+
        # @return [Symbol] +:opcode+, +:dop1+ or +:dop2+
        # @raise [ActionUnavailableError] when the app has no such action for the hood's protocol
        def route(kind)
          ROUTES.fetch(kind)[protocol_version] ||
            raise(ActionUnavailableError, "the app has no such action for a protocol #{protocol_version} hood")
        end

        # @param request [String]
        # @return [void]
        def opcode(request) = send_request(:post, "/Devices/#{fab}/Oc85/", body: JSON.generate('Request' => request))

        # SetFanPowerLevelOpCodeAction posts the same request again half a second later.
        #
        # @param request [String]
        # @return [void]
        def opcode_twice(request)
          opcode(request)
          @sleeper.call(0.5)
          opcode(request)
        end

        # GlobalPsSelectBaseAction.DefaultBytes: every hood selection parameter at FFFF but the ones given.
        #
        # @param values [Hash{Integer=>Integer}] +GLOBAL_PS_SelectionParaHood+ members: 1 fan level, 2 run-on
        # @return [Dop2::Leaf] 2/1577 at idx 1/1
        def hood_select(values)
          members = (1..21).to_h { [it, Dop2::Field.new(type: :u16, value: values.fetch(it, 0xFFFF))] }
          Dop2::Leaf.new(unit: 2, attribute: 1577, idx1: 1, idx2: 1,
                         fields: { 10 => Dop2::Field.new(type: :struct, value: members) })
        end

        # The app reads 2/1583 at 0/1 and writes it back there with the request set.
        #
        # @param id [Integer] a +GLOBAL_EnumUserRequestId+ value
        # @return [void]
        def dop2_user_request(id)
          leaf = dop2(2, 1583, idx1: 0, idx2: 1)
          request = Dop2::Field.new(type: leaf.fields[1]&.type || :e16, value: id)
          write_modified(leaf.with(fields: leaf.fields.merge(1 => request)), 1583, 0)
        end

        # @param id [Integer] a +GLOBAL_EnumSfId+ value
        # @param value [Integer]
        # @return [void]
        def write_sf(id, value)
          leaf = dop2(2, 105, idx1: id, idx2: 1)
          fields = Objects::Hood::GlobalSfValue.from(leaf.fields).with(current_value: value).to_fields
          write_modified(leaf.with(fields:), 105, id)
        end

        # ModifyDop2Message: the app sends the index it read at as the header's attribute, and as both indexes of
        # an instance read above 0, back where it read with idx2 1.
        #
        # @param leaf [Dop2::Leaf] as read, changed
        # @param attribute [Integer] where it was read, on unit 2
        # @param index [Integer] the idx1 it was read at
        # @return [void]
        def write_modified(leaf, attribute, index)
          leaf = leaf.with(idx1: index, idx2: index) if leaf.idx1.positive?
          body = Dop2.encode(leaf.with(attribute: index))
          send_request(:put, "#{dop2_path(2, attribute)}?idx1=#{index}&idx2=1", body:, kind: :dop2)
        end
      end
    end
  end
end
