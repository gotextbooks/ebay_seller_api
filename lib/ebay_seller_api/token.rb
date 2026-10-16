# frozen_string_literal: true

module EbaySellerApi
  class Token
    EXPIRATION_OFFSET_SECONDS = 60

    def initialize(data)
      @data = data.to_h.stringify_keys
      expires_in = @data['expires_in']
      @expires_at = Time.current + expires_in.to_i - EXPIRATION_OFFSET_SECONDS
    end

    def access_token
      @data['access_token']
    end

    def refresh_token
      @data['refresh_token']
    end

    def usable?
      access_token.present? && @expires_at.future?
    end

    def to_h
      @data.dup
    end
  end
end
