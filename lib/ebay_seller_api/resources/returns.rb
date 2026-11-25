# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Returns < Base
      BASE_PATH = '/post-order/v2/return'

      def get_return(return_id)
        get("/#{segment(return_id)}")
      end

      def decide(return_id, body)
        post("/#{segment(return_id)}/decide", body)
      end

      def issue_refund(return_id, body)
        post("/#{segment(return_id)}/issue_refund", body)
      end

      private

      def request(method, path, options)
        super(method, path, options.merge(auth_scheme: 'IAF'))
      end
    end
  end
end
