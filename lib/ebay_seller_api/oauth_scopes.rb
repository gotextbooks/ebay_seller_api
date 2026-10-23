# frozen_string_literal: true

module EbaySellerApi
  module OAuthScopes
    API = 'https://api.ebay.com/oauth/api_scope'
    SELL_INVENTORY = 'https://api.ebay.com/oauth/api_scope/sell.inventory'
    SELL_FULFILLMENT = 'https://api.ebay.com/oauth/api_scope/sell.fulfillment'
    SELL_FULFILLMENT_READONLY = 'https://api.ebay.com/oauth/api_scope/sell.fulfillment.readonly'
    NOTIFICATION_SUBSCRIPTION = 'https://api.ebay.com/oauth/api_scope/commerce.notification.subscription'
    TOPICS = {
      'ORDER_CONFIRMATION' => [SELL_FULFILLMENT, SELL_FULFILLMENT_READONLY]
    }.freeze

    CONSENT = [
      API,
      SELL_INVENTORY,
      SELL_FULFILLMENT,
      SELL_FULFILLMENT_READONLY,
      NOTIFICATION_SUBSCRIPTION
    ].freeze

    def self.topic(topic_id)
      TOPICS.fetch(topic_id) { raise ArgumentError, "Unknown notification topic: #{topic_id}" }
    end
  end
end
