# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Base
      attr_reader :client, :scope

      def initialize(client, scope: self.class::SCOPE)
        @client = client
        @scope = scope
      end

      def base_path
        self.class::BASE_PATH
      end

      protected

      def get(path, **options)
        request(:get, path, options)
      end

      def post(path, body = nil, **options)
        request(:post, path, options.merge(body:))
      end

      def put(path, body = nil, **options)
        request(:put, path, options.merge(body:))
      end

      def delete(path, **options)
        request(:delete, path, options)
      end

      def segment(value)
        URI.encode_uri_component(value.to_s)
      end

      private

      def request(method, path, options)
        client.public_send(method, "#{base_path}#{path}", options.reverse_merge(scope:))
      end
    end
  end
end
