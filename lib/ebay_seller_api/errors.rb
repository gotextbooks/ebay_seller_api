# frozen_string_literal: true

module EbaySellerApi
  class Error < StandardError; end

  module FeedUploadError
    attr_accessor :task_id
  end

  class FeedFileError < Error
    include FeedUploadError

    def initialize(message, task_id:)
      super(message)
      self.task_id = task_id
    end
  end

  class ApiError < Error
    FEED_LIMIT_ERROR_IDS = [160_024, 160_025].freeze
    NO_DATA = { 'message' => 'eBay API Error', 'description' => 'No data is set in response result.' }.freeze
    UNKNOWN = {
      'message' => 'Unknown eBay API Error',
      'description' => 'This error response is not known. You should investigate the response body.'
    }.freeze

    attr_reader :status_code, :response_body, :response_headers, :description, :error_code, :first_error

    def initialize(message, status_code = nil, response_body = nil, response_headers = nil, **details)
      super(message)
      @status_code = status_code
      @response_body = response_body
      @response_headers = response_headers
      @description = details[:description]
      @error_code = details[:error_code]
      @first_error = details[:first_error]
    end

    def self.from_response(response)
      error = first_error_in(response.body)
      description = error['description'] || error['longMessage'] || response.reason_phrase.to_s

      error_class(error, response.status).new(
        error['message'] || 'eBay API request error', response.status, response.body, response.headers,
        description:, error_code: error['errorId'], first_error: error
      )
    end

    # The status-based class, for errors without an eBay error body (e.g. invalid JSON).
    def self.for_status(status)
      status_error_class(status)
    end

    class ValidationError < ApiError; end
    class AuthenticationError < ApiError; end
    class AuthorizationError < ApiError; end
    class NotFoundError < ApiError; end
    class RateLimitError < ApiError; end
    class ServerError < ApiError; end
    class NetworkError < ApiError; end
    class InvalidAccessToken < AuthenticationError; end
    class InvalidGrant < ApiError; end
    class InvalidScope < ApiError; end

    class << self
      private

      def first_error_in(body)
        return NO_DATA if body.blank?

        data = body.is_a?(String) ? JSON.parse(body) : body
        (first_error_in_hash(data) if data.is_a?(Hash)) || UNKNOWN
      rescue JSON::ParserError
        { 'message' => body } # not JSON, e.g. a gateway's HTML or plain-text page
      end

      def first_error_in_hash(data)
        if data['error'].is_a?(String) # OAuth token endpoint
          { 'message' => data['error'], 'description' => data['error_description'].to_s }
        elsif data['errors'].is_a?(Array) # REST APIs
          data['errors'].first
        end
      end

      def error_class(error, status)
        message = error['message']

        if message == 'invalid_grant' then InvalidGrant
        elsif message == 'invalid_scope' then InvalidScope
        elsif message == 'Invalid access token' then InvalidAccessToken
        elsif FEED_LIMIT_ERROR_IDS.include?(error['errorId']) then RateLimitError
        else status_error_class(status)
        end
      end

      def status_error_class(status)
        case status
        when 400, 422 then ValidationError
        when 401 then AuthenticationError
        when 403 then AuthorizationError
        when 404 then NotFoundError
        when 429 then RateLimitError
        when 500..599 then ServerError
        else self
        end
      end
    end
  end
end
