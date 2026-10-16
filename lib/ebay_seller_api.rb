# frozen_string_literal: true

require 'faraday'
require 'json'
require 'uri'
require 'active_support'
require 'active_support/core_ext'
require 'dry-configurable'

require_relative 'ebay_seller_api/version'
require_relative 'ebay_seller_api/configuration'
require_relative 'ebay_seller_api/errors'
require_relative 'ebay_seller_api/token'
require_relative 'ebay_seller_api/oauth2'
require_relative 'ebay_seller_api/multipart_body'
require_relative 'ebay_seller_api/client'
require_relative 'ebay_seller_api/resources/base'
require_relative 'ebay_seller_api/resources/feed_upload'
require_relative 'ebay_seller_api/resources/listings'
require_relative 'ebay_seller_api/resources/orders'
require_relative 'ebay_seller_api/resources/tasks'

module EbaySellerApi
  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def oauth
      client.oauth
    end

    def listings
      @listings ||= Resources::Listings.new(client)
    end

    def orders
      @orders ||= Resources::Orders.new(client)
    end

    def tasks
      @tasks ||= Resources::Tasks.new(client)
    end

    def reset!
      instance_variables.each do |ivar|
        instance_variable_set(ivar, nil) unless ivar == :@config
      end
    end

    private

    def client
      @client ||= Client.new
    end
  end
end
