# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Notifications < Base
      BASE_PATH = '/commerce/notification/v1'
      APPLICATION = { application_token: true }.freeze

      def self.created_id(response)
        response.headers['location'].to_s.split('/').last.presence
      end

      def update_config(data)
        put('/config', data, **APPLICATION)
      end

      def create_destination(data)
        post('/destination', data, **APPLICATION)
      end

      def get_destination(destination_id)
        require_id!(:destination_id, destination_id)

        get("/destination/#{segment(destination_id)}", **APPLICATION)
      end

      def create_subscription(data)
        post('/subscription', data)
      end

      def get_subscription(subscription_id)
        require_id!(:subscription_id, subscription_id)

        get("/subscription/#{segment(subscription_id)}")
      end

      def test_subscription(subscription_id)
        require_id!(:subscription_id, subscription_id)

        post("/subscription/#{segment(subscription_id)}/test")
      end

      def get_public_key(public_key_id)
        require_id!(:public_key_id, public_key_id)

        get("/public_key/#{segment(public_key_id)}", **APPLICATION)
      end

      private

      def require_id!(name, id)
        raise ArgumentError, "Missing required argument: #{name}" if id.blank?
      end
    end
  end
end
