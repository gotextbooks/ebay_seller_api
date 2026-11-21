# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Base
      attr_reader :client

      def initialize(client)
        @client = client
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

      # eBay returns a created resource's ID as the last segment of the Location header
      def id_from_location(response, label)
        id = response.headers['location'].to_s.split('/').last
        raise Error, "eBay returned no #{label} ID (missing location header)" if id.blank?

        id
      end

      def require_id!(name, id)
        raise ArgumentError, "Missing required argument: #{name}" if id.blank?
      end

      private

      def request(method, path, options)
        url = "#{base_path}#{path}"
        url = "#{client.configuration.apiz_url}#{url}" if options.delete(:apiz)
        client.public_send(method, url, options)
      end
    end
  end
end
