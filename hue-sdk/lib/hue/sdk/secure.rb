# frozen_string_literal: true

require_relative '../sdk'
require_relative 'secure/configuration'
require_relative 'secure/http'
require_relative 'secure/token'
require_relative 'secure/session'
require_relative 'secure/client'
require_relative 'secure/wire'
require_relative 'secure/e2ee'
require_relative 'secure/media'
require_relative 'secure/mp4'
require_relative 'secure/clip'
require_relative 'secure/clip_proxy'
require_relative 'secure/home'
require_relative 'secure/schema/arm'
require_relative 'secure/schema/cameras'
require_relative 'secure/schema/events'
require_relative 'secure/schema/media'
require_relative 'secure/arm'
require_relative 'secure/schedules'
require_relative 'secure/geofence'
require_relative 'secure/camera'
require_relative 'secure/cameras'
require_relative 'secure/events'
require_relative 'secure/follow'

module Hue
  module Sdk
    # Hue Secure through the Hue account's cloud, apart from the bridge: +require 'hue/sdk/secure'+. Never tested on
    # a device.
    #
    # @example Log in once, then reuse the saved token
    #   Hue::Sdk::Secure.configure do |config|
    #     config.client_id = ENV.fetch('HUE_ACCOUNT_CLIENT_ID')
    #     config.token_file = 'hue-account.json'
    #   end
    #   puts Hue::Sdk::Secure.session.authorize_url
    #   Hue::Sdk::Secure.session.exchange(gets.chomp)
    module Secure
      extend Configuration

      LOCK = Mutex.new
      private_constant :LOCK

      # @return [Session] the account's session, kept until the settings change
      # @api public
      def self.session = LOCK.synchronize { @session ||= Session.new }

      # @return [Client] requests to the cloud with the session's token
      # @api public
      def self.client = Client.new(session)

      # @return [Array<Home>] the homes of the account
      # @raise (see Home.list)
      # @api public
      def self.homes = Home.list(session)

      # @param id [String]
      # @return [Home] the home of this id, without a request
      # @api public
      def self.home(id) = Home.new(id:)

      # @return [Schema::FetchedAutoResponseConfiguration] the automatic responses a doorbell may play, chosen on the
      #   camera with {Camera#update_bell_button}
      # @raise (see Http.request)
      # @api public
      def self.auto_responses
        manifest = client.get("#{config.auto_responses_url}/automatic_response/manifest.json").body
        Schema::FetchedAutoResponseConfiguration.from(manifest)
      end

      # Changes the settings; the next session reads them.
      #
      # @yieldparam config [Configuration::Settings]
      # @return [void]
      # @api public
      def self.configure(&)
        super
        LOCK.synchronize { @session = nil }
      end
    end
  end
end
