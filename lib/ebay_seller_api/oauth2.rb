# frozen_string_literal: true

module EbaySellerApi
  class OAuth2
    attr_reader :configuration

    def self.tokens
      @tokens ||= {}
    end

    def initialize(client, configuration = client.configuration)
      @client = client
      @configuration = configuration
      @refresh_token = configuration.refresh_token
    end

    def generate_auth_url(scope: Resources::CONSENT_SCOPES, state: '')
      ru_name = configuration.ru_name
      raise ArgumentError, 'RuName is required.' if ru_name.blank?

      [
        configuration.authorize_endpoint,
        '?client_id=', encode(configuration.client_id),
        '&redirect_uri=', encode(ru_name),
        '&response_type=code',
        '&state=', encode(state),
        '&scope=', encode(Array(scope).join(' '))
      ].join
    end

    def access_token(scope)
      token = self.class.tokens[token_key(scope)]
      return token.access_token if token&.usable?
      raise ArgumentError, 'refresh_token is required to request an access token' if @refresh_token.blank?

      refresh_user_access_token(scope)['access_token']
    end

    def get_token(code, ru_name = configuration.ru_name)
      request_token(grant_type: 'authorization_code', code:, redirect_uri: ru_name)
    end

    def obtain_token(code)
      token = get_token(code)
      self.credentials = token
      token
    end

    def refresh_user_access_token(scope)
      raise Error, 'Failed to refresh the user access token. refresh_token is not set.' if @refresh_token.blank?

      request_token(grant_type: 'refresh_token', refresh_token: @refresh_token, scope: Array(scope).join(' '))
        .tap { |token| self.class.tokens[token_key(scope)] = build_token(token) }
    end

    def application_access_token(refresh: false)
      token = self.class.tokens[application_token_key] unless refresh
      return token.access_token if token&.usable?

      data = request_token(grant_type: 'client_credentials', scope: Configuration::DEFAULT_SCOPE.join(' '))
      self.class.tokens[application_token_key] = build_token(data)
      data['access_token']
    end

    def credentials=(token)
      refresh_token = token.to_h.stringify_keys['refresh_token']
      @refresh_token = refresh_token if refresh_token.present?
    end

    private

    def token_key(scope)
      [configuration.environment, configuration.client_id, @refresh_token, Array(scope).sort]
    end

    def application_token_key
      [configuration.environment, configuration.client_id, :application]
    end

    def request_token(params)
      @client.token_request(params).body
    end

    def build_token(data)
      Token.new(data)
    end

    def encode(value)
      URI.encode_uri_component(value.to_s)
    end
  end
end
