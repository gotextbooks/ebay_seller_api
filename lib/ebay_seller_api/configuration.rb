# frozen_string_literal: true

module EbaySellerApi
  class Configuration
    include Dry::Configurable

    ENVIRONMENTS = %i[sandbox production].freeze

    setting :client_id
    setting :client_secret
    setting :ru_name
    setting :scopes
    setting :environment, default: :sandbox
    setting :refresh_token
    setting :marketplace_id, default: 'EBAY_US'
    setting :content_language, default: 'en-US'
    setting :accept_language, default: 'en-US'
    setting :timeout, default: 30
    setting :open_timeout, default: 10
    setting :logger
    setting :listing_schema_version, default: '1487'
    setting :order_report_schema_version, default: '1355'
    setting :order_ack_schema_version, default: '1.0'

    delegate_missing_to :config

    def sandbox?
      environment == :sandbox
    end

    def api_url
      "https://api.#{'sandbox.' if sandbox?}ebay.com"
    end

    def identity_endpoint
      "#{api_url}/identity/v1/oauth2/token"
    end

    def authorize_endpoint
      "https://auth.#{'sandbox.' if sandbox?}ebay.com/oauth2/authorize"
    end

    def validate!
      raise ArgumentError, 'client_id is required' if client_id.blank?
      raise ArgumentError, 'client_secret is required' if client_secret.blank?
      return if ENVIRONMENTS.include?(environment)

      raise ArgumentError, "Invalid environment: #{environment}. Must be :sandbox or :production"
    end
  end
end
