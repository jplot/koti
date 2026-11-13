# frozen_string_literal: true

require 'base64'
require 'time'

module Hue
  module Sdk
    module Secure
      # The media of the cameras of a home, which the cameras encrypt end to end with keys of the home's passphrase:
      # the gem decrypts them as the app does. Never tested on a device.
      class Media
        # An image of a camera, in clear.
        #
        # @!attribute [r] image
        #   @return [String] the JPEG
        # @!attribute [r] timestamp
        #   @return [String]
        # @!attribute [r] refresh_timestamp
        #   @return [String, nil] for the latest snapshot only
        Snapshot = Data.define(:image, :timestamp, :refresh_timestamp)

        # @return [String]
        attr_reader :home_id

        # @return [String] the id of the home signing key the passphrase matches, which a live view sends
        attr_reader :signing_key_id

        # Checks the passphrase as the app does when it is given one: its home signing key must be the newest the
        # key service publishes for the home.
        #
        # @param home_id [String]
        # @param passphrase [String] the five words, exactly as the app was given them
        # @return [Media]
        # @raise [E2eeError] if the passphrase is an old one, or does not open the home
        # @api private
        def self.open(home_id, passphrase)
          keys = E2ee::Keys.new(passphrase)
          derived = E2ee.raw(keys.home_signing)
          newest, *older = published(home_id)
          return new(home_id, keys, newest.id) if newest && signed?(newest, derived)
          raise E2eeError, 'the passphrase is an old one' if older.any? { signed?(it, derived) }

          raise E2eeError, 'the passphrase is wrong'
        end

        # @param home_id [String]
        # @return [Array<Schema::PublicKeyResponse>] the home signing keys the key service publishes, newest first
        # @api private
        def self.published(home_id)
          Secure.client.get("security/E2EE-public-keys-service/v1/home/#{home_id}/e2ee/public-key",
                            query: { key_type: 'home_signing_public_key' }).body
                .map { Schema::PublicKeyResponse.from(it) }.sort_by { Time.parse(it.upload_date) }.reverse
        end

        # @param key [Schema::PublicKeyResponse]
        # @param derived [String]
        # @return [Boolean]
        # @api private
        def self.signed?(key, derived) = E2ee.raw(OpenSSL::PKey::EC.new(key.public_key)) == derived

        private_class_method :published, :signed?

        # @param home_id [String]
        # @param keys [E2ee::Keys]
        # @param signing_key_id [String]
        # @api private
        def initialize(home_id, keys, signing_key_id)
          @home_id = home_id
          @keys = keys
          @signing_key_id = signing_key_id
        end

        # A camera's latest snapshot, or the one of an event of the timeline.
        #
        # @param camera_id [String]
        # @param at [Time, nil] the event's device time; nil for the latest snapshot
        # @return [Snapshot]
        # @raise [E2eeError] if the image does not decrypt
        # @raise [ResponseError] if the cloud refuses
        # @raise [ConnectionError] if the cloud cannot be reached
        def snapshot(camera_id, at: nil)
          path = "security/event-service/v1/home/#{home_id}/device/#{camera_id}/timestamp/#{at&.to_i || 'latest'}/" \
                 'snapshot'
          read = at ? Schema::DownloadTimelineEventSnapshotResponse : Schema::DownloadCameraLastSnapshotResponse
          answer = read.from(Secure.client.get(path).body)
          image = decrypted(Base64.strict_decode64(answer.snapshot), camera_id)
          Snapshot.new(image:, timestamp: answer.timestamp, refresh_timestamp: answer.to_h[:refresh_timestamp])
        end

        # The image behind the +snapshot_url+ of an event, which carries its own authorization: a refusal, such as an
        # expired URL, is not the account's token.
        #
        # @param camera_id [String] the camera of the event
        # @param url [String]
        # @return [String] the JPEG
        # @raise [E2eeError] if the image does not decrypt
        # @raise [ResponseError] if the URL is refused
        # @raise [ConnectionError] if its host cannot be reached
        def snapshot_at(camera_id, url)
          uri = URI(url) #: URI::HTTP
          answer = Http.exchange(uri, Net::HTTP::Get.new(uri, { 'User-Agent' => "hue-sdk/#{VERSION}" }))
          raise ResponseError.new(answer.code.to_i, [], source: uri.host.to_s) unless answer.is_a?(Net::HTTPSuccess)

          decrypted(answer.body.to_s, camera_id)
        end

        private

        def decrypted(blob, camera_id)
          cek, box = E2ee.open(blob, keys: @keys, camera_id:)
          E2ee.decrypt(cek, box)
        end
      end
    end
  end
end
