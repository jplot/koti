# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # A home of the Hue account, as +BasicHome+ gives it. Named by its id alone, every other attribute is nil.
      #
      # @!attribute [r] id
      #   @return [String]
      # @!attribute [r] name
      #   @return [String, nil]
      # @!attribute [r] user_count
      #   @return [Integer, nil]
      # @!attribute [r] max_users
      #   @return [Integer, nil]
      # @!attribute [r] admin_count
      #   @return [Integer, nil]
      # @!attribute [r] revision
      #   @return [Integer, nil]
      # @!attribute [r] permissions
      #   @return [Array<String>, nil] what the account may do in the home, such as +security.arm.state.update+
      # @!attribute [r] country_code
      #   @return [String, nil]
      # @!attribute [r] time_zone
      #   @return [String, nil]
      # @!attribute [r] security_activated
      #   @return [Boolean, nil]
      # @!attribute [r] bridges
      #   @return [Array<String>, nil] ids of the home's bridges
      Home = Data.define(:id, :name, :user_count, :max_users, :admin_count, :revision, :permissions, :country_code,
                         :time_zone, :security_activated, :bridges)

      # A home of the Hue account.
      class Home
        LIST = '/hue.accounts.v1.HomeService/ListHomes'
        private_constant :LIST

        ABSENT = (members - [:id]).to_h { [it, nil] }.freeze
        private_constant :ABSENT

        TEXTS = { name: 2, country_code: 10, time_zone: 11 }.freeze
        private_constant :TEXTS

        NUMBERS = { user_count: 3, max_users: 5, admin_count: 7, revision: 8 }.freeze
        private_constant :NUMBERS

        # @param id [String]
        # @param attributes [Hash{Symbol=>Object}] the other members, nil when not given
        # @api public
        def initialize(id:, **attributes) = super(id:, **ABSENT, **attributes)

        # @return [Arm] the arming of the home and its alarm
        # @api public
        def arm = Arm.new(id)

        # @return [Schedules] the schedules that arm and disarm the home
        # @api public
        def schedules = Schedules.new(id)

        # @return [Geofence] the phones whose presence arms and disarms the home
        # @api public
        def geofence = Geofence.new(id)

        # @return [Cameras] the cameras of the home
        # @api public
        def cameras = Cameras.new(id)

        # The app lists the homes over gRPC, and no REST path gives them. grpc is loaded here only.
        #
        # @param session [Session]
        # @return [Array<Home>]
        # @raise [Error] without the grpc gem
        # @raise (see .listed)
        # @api public
        def self.list(session)
          begin
            require 'grpc'
          rescue LoadError
            raise Error, "listing the Hue homes needs the grpc gem: add gem 'grpc' to your Gemfile"
          end
          listed(session)
        end

        # @param session [Session]
        # @return [Array<Home>]
        # @raise (see .translated)
        # @api private
        def self.listed(session)
          metadata = { 'authorization' => "Bearer #{session.current.value}" }
          answer = stub.request_response(LIST, '', ->(_) { '' }, ->(bytes) { bytes }, metadata:)
          Wire.texts(Wire.decode(answer), 1).map { decode(it) }
        rescue GRPC::BadStatus => e
          raise translated(e)
        end

        # @return [GRPC::ClientStub]
        # @api private
        def self.stub
          config = Secure.config
          GRPC::ClientStub.new(config.grpc_target, config.grpc_credentials || GRPC::Core::ChannelCredentials.new,
                               timeout: config.read_timeout)
        end

        # @param status [GRPC::BadStatus]
        # @return [Error]
        # @raise [AuthenticationError] if the cloud refuses the token
        # @raise [ConnectionError] if the cloud cannot be reached in +read_timeout+
        # @raise [Error] on any other gRPC status
        # @api private
        def self.translated(status)
          case status
          when GRPC::Unauthenticated, GRPC::PermissionDenied
            AuthenticationError.new("the Hue account refused the token (gRPC #{status.code}: #{status.details})")
          when GRPC::Unavailable, GRPC::DeadlineExceeded
            ConnectionError.new("#{Secure.config.grpc_target}: #{status.details}")
          else Error.new("Hue cloud answered gRPC #{status.code}: #{status.details}")
          end
        end

        # @param bytes [String] a +BasicHome+
        # @return [Home]
        # @api private
        def self.decode(bytes)
          fields = Wire.decode(bytes)
          new(id: Wire.text(fields, 1), **TEXTS.transform_values { Wire.text(fields, it) },
              **NUMBERS.transform_values { Wire.number(fields, it) }, permissions: Wire.texts(fields, 9),
              security_activated: Wire.number(fields, 13).positive?,
              bridges: Wire.texts(fields, 4).map { Wire.text(Wire.decode(it), 1) })
        end
      end
    end
  end
end
