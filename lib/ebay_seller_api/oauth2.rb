# frozen_string_literal: true

module EbaySellerApi
  class OAuth2
    attr_reader :configuration, :scope

    # Tokens outlive clients, so a new client after EbaySellerApi.reset! reuses a still-valid access token instead of
    # requesting a new one. Keyed by environment, client ID, refresh token and scope; one per process.
    def self.tokens
      @tokens ||= {}
    end

    def initialize(client, configuration = client.configuration)
      @client = client
      @configuration = configuration
      @scope = Array(configuration.scope)
      refresh_token = configuration.refresh_token
      return if refresh_token.blank?

      @auth_token = self.class.tokens[token_key(refresh_token)] || build_token({ 'refresh_token' => refresh_token })
    end

    def generate_auth_url(ru_name: configuration.ru_name, scope: self.scope, state: '')
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

    def access_token
      return @auth_token.access_token if @auth_token&.usable?
      raise ArgumentError, 'refresh_token is required to request an access token' if @auth_token&.refresh_token.blank?

      refresh_user_access_token['access_token']
    end

    def get_token(code, ru_name = configuration.ru_name)
      request_token(grant_type: 'authorization_code', code:, redirect_uri: ru_name)
    end

    def obtain_token(code)
      token = get_token(code)
      self.credentials = token
      token
    end

    def refresh_user_access_token
      if @auth_token&.refresh_token.blank?
        raise Error, 'Failed to refresh the user access token. Token or refresh_token is not set.'
      end

      token = request_token(grant_type: 'refresh_token', refresh_token: @auth_token.refresh_token,
                            scope: scope.join(' '))
      @auth_token.to_h.merge(token).tap { |refreshed| self.credentials = refreshed }
    end

    def credentials=(token)
      @auth_token = build_token(token)
      self.class.tokens[token_key(@auth_token.refresh_token)] = @auth_token if @auth_token.refresh_token.present?
    end

    private

    def token_key(refresh_token)
      [configuration.environment, configuration.client_id, refresh_token, scope]
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
