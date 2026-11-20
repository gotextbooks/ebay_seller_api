# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Notifications < Base
      BASE_PATH = '/commerce/notification/v1'

      def self.created_id(response)
        response.headers['location'].to_s.split('/').last.presence
      end

      def update_config(data)
        put('/config', data, **app_token_params)
      end

      def get_destinations(params = {})
        get('/destination', query: params, **app_token_params)
      end

      def create_destination(data)
        post('/destination', data, **app_token_params)
      end

      def get_destination(destination_id)
        require_id!(:destination_id, destination_id)

        get("/destination/#{segment(destination_id)}", **app_token_params)
      end

      def update_destination(destination_id, data)
        require_id!(:destination_id, destination_id)

        put("/destination/#{segment(destination_id)}", data, **app_token_params)
      end

      def delete_destination(destination_id)
        require_id!(:destination_id, destination_id)

        delete("/destination/#{segment(destination_id)}", **app_token_params)
      end

      def get_topic(topic_id)
        require_id!(:topic_id, topic_id)

        get("/topic/#{segment(topic_id)}", **app_token_params)
      end

      def get_subscriptions(params = {})
        get('/subscription', query: params)
      end

      def create_subscription(data)
        post('/subscription', data)
      end

      def get_subscription(subscription_id)
        require_id!(:subscription_id, subscription_id)

        get("/subscription/#{segment(subscription_id)}")
      end

      def update_subscription(subscription_id, data)
        require_id!(:subscription_id, subscription_id)

        put("/subscription/#{segment(subscription_id)}", data)
      end

      def delete_subscription(subscription_id)
        require_id!(:subscription_id, subscription_id)

        delete("/subscription/#{segment(subscription_id)}")
      end

      def enable_subscription(subscription_id)
        require_id!(:subscription_id, subscription_id)

        post("/subscription/#{segment(subscription_id)}/enable")
      end

      def disable_subscription(subscription_id)
        require_id!(:subscription_id, subscription_id)

        post("/subscription/#{segment(subscription_id)}/disable")
      end

      def test_subscription(subscription_id)
        require_id!(:subscription_id, subscription_id)

        post("/subscription/#{segment(subscription_id)}/test")
      end

      def get_public_key(public_key_id)
        require_id!(:public_key_id, public_key_id)

        get("/public_key/#{segment(public_key_id)}", **app_token_params)
      end

      private

      def app_token_params
        { application_token: true }
      end

      def require_id!(name, id)
        raise ArgumentError, "Missing required argument: #{name}" if id.blank?
      end
    end
  end
end
