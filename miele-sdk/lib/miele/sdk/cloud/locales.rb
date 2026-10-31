# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    # The Miele cloud, which the Miele app talks to appliances through once they are paired.
    module Cloud
      # Where each country's cloud lives, and how its accounts log in, as the app reads it.
      module Locales
        # A Miele sales organization.
        #
        # @!attribute [r] iso
        #   @return [String] its code, which the login names
        # @!attribute [r] rest
        #   @return [String] address of its cloud, scheme included
        # @!attribute [r] ciam
        #   @return [Boolean] whether its accounts log in through CIAM (a web page) instead of MCS (e-mail and
        #     password)
        # @!attribute [r] ciam_endpoints
        #   @return [Hash{String=>String}] the +authorize+, +token+ and +logout+ addresses of CIAM
        # @!attribute [r] bundled
        #   @return [Boolean] whether it comes from the copy the app bundles, which may be out of date
        Organization = Data.define(:iso, :rest, :ciam, :ciam_endpoints, :bundled)

        # A Miele sales organization.
        class Organization
          # @param bundled [Boolean]
          # @param fields [Hash] the other members
          def initialize(bundled: false, **fields) = super
        end

        # The copy the app falls back on when the cloud does not answer, reduced by +schema/extract/locales.rb+.
        BUNDLED = "#{__dir__}/locales.json".freeze
        private_constant :BUNDLED

        module_function

        # @param country [String] ISO code of the account's country
        # @return [Organization]
        # @raise [ConfigurationError] for a country the app does not know
        # @api public
        def organization(country)
          host = Sdk.config.locales_host
          iso = fetch("#{host}/V3/Locales/Countries").find { |entry| codes(entry).include?(country) }
                                                     &.dig('organization', 'iso')
          company = iso && fetch("#{host}/V3/Locales?org=#{iso}").first
          company ? from_company(company) : unknown(country)
        rescue ConnectionError, ResponseError, JSON::ParserError
          bundled(country)
        end

        # @param url [String]
        # @return [Array<Hash>]
        # @raise [ConnectionError, ResponseError, JSON::ParserError]
        # @api private
        def fetch(url)
          answer = Http.request(:get, url)
          raise ResponseError.new(answer.status, "cloud answered #{answer.status}") unless answer.status == 200

          JSON.parse(answer.body)
        end

        # @param entry [Hash] an organization and its countries
        # @return [Array<String>]
        # @api private
        def codes(entry) = entry.fetch('countries', []).map { it['iso'] }

        # @param company [Hash] a sales company as the cloud serves it
        # @return [Organization]
        # @api private
        def from_company(company)
          rest = company.dig('mcsConfig', 'dnsNames').find { it['type'] == 'rest' }.fetch('host')
          endpoints = company.dig('ciam', 'endpoints').to_a.to_h { [it['type'], it['uri']] }
          organization_of(company.dig('organization', 'iso'), rest, company.dig('ciam', 'active') == true, endpoints)
        end

        # @param country [String]
        # @return [Organization]
        # @raise [ConfigurationError]
        # @api private
        def bundled(country)
          entry = JSON.parse(File.read(BUNDLED)).find { it['countries'].include?(country) } or unknown(country)
          organization_of(entry['iso'], entry['rest'], entry['ciam'], entry['ciam_endpoints']).with(bundled: true)
        end

        # The app adds +https://+ only to a host that has no scheme.
        #
        # @return [Organization]
        # @api private
        def organization_of(iso, rest, ciam, endpoints)
          rest = "https://#{rest}" unless rest.include?('://')
          Organization.new(iso:, rest:, ciam:, ciam_endpoints: endpoints.slice('authorize', 'token', 'logout'))
        end

        # @param country [String]
        # @return [void]
        # @raise [ConfigurationError]
        # @api private
        def unknown(country) = raise(ConfigurationError, "the Miele app knows no cloud for the country #{country}")
      end
    end
  end
end
