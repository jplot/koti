# frozen_string_literal: true

require 'time'

module Hue
  module Sdk
    module Secure
      # Kinesis Video Streams, where the cameras store their clips: the gem downloads one through AWS's own gems, signed
      # with credentials the Hue cloud hands out for that clip.
      module Kinesis
        PURPOSE = 'downloading a Hue Secure clip'
        private_constant :PURPOSE

        module_function

        # @param credential [Schema::ClipCredentials]
        # @param metadata [Schema::ClipMetadata]
        # @return [String] the MP4 file, its samples sealed
        # @raise [Error] without the AWS gems
        # @raise [ResponseError] if Kinesis Video refuses
        # @raise [ConnectionError] if Kinesis Video cannot be reached
        # @api private
        def clip(credential, metadata)
          %w[aws-sdk-kinesisvideo aws-sdk-kinesisvideoarchivedmedia].each { Media.load(it, PURPOSE) }
          fetched(options(credential), metadata)
        end

        # One attempt, as the app makes, within the gem's timeouts: AWS's clients would try 3 times, and wait up to
        # 15 s to connect and 60 s to read.
        def options(credential)
          config = Secure.config
          { region: config.kinesis_region, retry_mode: 'standard', max_attempts: 1,
            http_open_timeout: config.open_timeout, http_read_timeout: config.read_timeout,
            credentials: Aws::Credentials.new(credential.accessKeyId, credential.secretAccessKey,
                                              credential.sessionToken) }
        end

        def fetched(options, metadata)
          stream_name = metadata.stream_name
          Aws::KinesisVideoArchivedMedia::Client.new(**options, endpoint: data_endpoint(options, stream_name))
                                                .get_clip(stream_name:, clip_fragment_selector: selector(metadata))
                                                .payload.read
        rescue Aws::Errors::ServiceError => e
          raise ResponseError.new(e.context.http_response.status_code, [e.message], source: 'Kinesis Video')
        rescue Seahorse::Client::NetworkingError => e
          raise ConnectionError, "Kinesis Video: #{e.message}"
        end

        def data_endpoint(options, stream_name)
          Aws::KinesisVideo::Client.new(**options, **{ endpoint: Secure.config.kinesis_url }.compact)
                                   .get_data_endpoint(stream_name:, api_name: 'GET_CLIP').data_endpoint
        end

        def selector(metadata)
          { fragment_selector_type: metadata.fragment_selector_type,
            timestamp_range: { start_timestamp: seconds(metadata.start_timestamp),
                               end_timestamp: seconds(metadata.end_timestamp) } }
        end

        # The app sends whole seconds.
        def seconds(timestamp) = Time.at(Time.parse(timestamp.to_s).to_i)

        private_class_method :options, :fetched, :data_endpoint, :selector, :seconds
      end
    end
  end
end
