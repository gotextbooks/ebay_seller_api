# frozen_string_literal: true

module EbaySellerApi
  class Client
    DEFAULT_HEADERS = {
      'Content-Type' => 'application/json',
      'Cache-Control' => 'no-cache'
    }.freeze
    CONFIG_HEADERS = {
      marketplace_id: 'X-EBAY-C-MARKETPLACE-ID',
      accept_language: 'Accept-Language',
      content_language: 'Content-Language'
    }.freeze
    FILTERED_KEYS = %w[code access_token refresh_token].freeze

    attr_reader :configuration, :oauth

    def initialize(configuration = nil)
      @configuration = configuration || EbaySellerApi.config
      @configuration.validate!
      @oauth = OAuth2.new(self, @configuration)
    end

    def get(path, options = {})
      make_request(:get, path, options)
    end

    def post(path, options = {})
      make_request(:post, path, options)
    end

    def put(path, options = {})
      make_request(:put, path, options)
    end

    def delete(path, options = {})
      make_request(:delete, path, options)
    end

    def token_request(form)
      make_request(:post, configuration.identity_endpoint, form:)
    end

    private

    def make_request(method, path, options = {})
      return send_request(method, path, options, nil) if options[:form]

      scope = options[:scope]
      raise ArgumentError, "An OAuth scope is required for #{method.upcase} #{path}" if scope.blank?

      access_token = oauth.access_token(scope)
      begin
        send_request(method, path, options, access_token)
      rescue ApiError::InvalidAccessToken
        oauth.refresh_user_access_token(scope)
        send_request(method, path, options, oauth.access_token(scope))
      end
    end

    def send_request(method, path, options, access_token)
      url = build_url(path)
      headers = build_headers(options, access_token)
      query = options[:query]&.compact.presence

      log_request(method, url, headers, loggable_body(options), query)
      response = binary_file_body(http_request(method, url, encode_body(options), headers, query))
      log_response(response)
      handle_response(response)
    end

    def http_request(method, url, body, headers, query)
      connection.run_request(method, url, body, headers) { |request| request.params.update(query) if query }
    rescue Faraday::ParsingError => e
      raise ApiError.for_status(e.response_status)
                    .new("Invalid JSON from eBay: #{e.message}", e.response_status, e.response_body)
    rescue Faraday::Error => e
      raise ApiError::NetworkError, "Network error: #{e.message}"
    end

    def handle_response(response)
      raise ApiError.from_response(response) unless response.success?

      response
    end

    def binary_file_body(response)
      body = response.body
      text = response.headers['content-type'].to_s.match?(%r{\Atext/|json|xml}i)
      body.force_encoding(Encoding::BINARY) if body.is_a?(String) && !text && !body.frozen?
      response
    end

    def build_url(path)
      path.start_with?('http') ? path : "#{configuration.api_url}#{path}"
    end

    def build_headers(options, access_token)
      headers = Faraday::Utils::Headers.new
      headers.update(options[:form] ? token_headers : api_headers(access_token))
      headers['Content-Type'] = options[:body].content_type if multipart?(options)
      headers
    end

    def api_headers(access_token)
      config_headers = CONFIG_HEADERS.to_h { |setting, header| [header, configuration.public_send(setting)] }
      DEFAULT_HEADERS.merge(config_headers.compact, 'Authorization' => "Bearer #{access_token}")
    end

    def token_headers
      {
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Accept' => 'application/json',
        'Authorization' => Faraday::Utils.basic_header_from(configuration.client_id, configuration.client_secret)
      }
    end

    def multipart?(options)
      options[:body].is_a?(MultipartBody)
    end

    def encode_body(options)
      return URI.encode_www_form(options[:form]) if options[:form]
      return options[:body].encode if multipart?(options)

      body = options[:body]
      body.is_a?(Hash) || body.is_a?(Array) ? body.to_json : body&.to_s
    end

    def loggable_body(options)
      return options[:body].log_summary if multipart?(options)

      options[:form] ? filter_keys(options[:form]) : options[:body]
    end

    def loggable_response_body(body)
      return filter_keys(body) if body.is_a?(Hash)
      return "[binary #{body.bytesize} bytes]" if body.is_a?(String) && body.encoding == Encoding::BINARY

      body
    end

    def filter_keys(hash)
      hash.to_h { |key, value| [key, FILTERED_KEYS.include?(key.to_s) ? '[FILTERED]' : value] }
    end

    def log_request(method, url, headers, body, query = nil)
      logger = configuration.logger
      return unless logger

      logger.info "eBay API Request: #{method.upcase} #{url}"
      logger.debug "Headers: #{headers.except('Authorization')}"
      logger.debug "Body: #{body.as_json}" if body
      logger.debug "Query: #{query}" if query
    end

    def log_response(response)
      logger = configuration.logger
      return unless logger

      logger.info "eBay API Response: #{response.status}"
      logger.debug "Response Headers: #{response.headers.to_h}"
      logger.debug "Response Body: #{loggable_response_body(response.body)}" if response.body.present?
    end

    def connection
      @connection ||= Faraday.new(
        request: {
          timeout: configuration.timeout,
          open_timeout: configuration.open_timeout,
          params_encoder: Faraday::FlatParamsEncoder # arrays as repeated keys: a=1&a=2
        }
      ) do |faraday|
        faraday.response :json, content_type: /\bjson$/
      end
    end
  end
end
