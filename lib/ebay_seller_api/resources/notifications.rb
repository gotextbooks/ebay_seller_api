# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Notifications < Base
      BASE_PATH = '/commerce/notification/v1'
      SCOPE = OAuthScopes::NOTIFICATION_SUBSCRIPTION

      def self.created_id(response)
        response.headers['location'].to_s.split('/').last.presence
      end

      def update_config(data)
        put('/config', data, **app_token_params)
      end

      def create_destination(data)
        post('/destination', data, **app_token_params)
      end

      def get_destination(destination_id)
        require_id!(:destination_id, destination_id)

        get("/destination/#{segment(destination_id)}", **app_token_params)
      end

      def get_topic(topic_id)
        require_id!(:topic_id, topic_id)

        get("/topic/#{segment(topic_id)}", **app_token_params)
      end

      def create_subscription(data)
        topic_id = data.with_indifferent_access[:topicId]
        require_id!(:topic_id, topic_id)

        post('/subscription', data, scope: [scope, *OAuthScopes.topic(topic_id)])
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
