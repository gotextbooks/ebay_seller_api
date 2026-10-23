# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Orders < Base
      include FeedUpload

      BASE_PATH = '/sell/fulfillment/v1'
      SCOPE = OAuthScopes::SELL_FULFILLMENT
      ORDER_REPORT_FEED_TYPE = 'LMS_ORDER_REPORT'
      ORDER_ACK_FEED_TYPE = 'LMS_ORDER_ACK'

      def get_order(order_id, params = {})
        get("/order/#{segment(order_id)}", query: params)
      end

      def get_orders(params = {})
        get('/order', query: params)
      end

      def create_order_report_task(filter_criteria = {})
        task_id_from(feed_tasks.create_order_task({
          feedType: ORDER_REPORT_FEED_TYPE,
          schemaVersion: client.configuration.order_report_schema_version,
          filterCriteria: filter_criteria.presence
        }.compact))
      end

      def get_order_report_task(task_id)
        require_task_id!(task_id)

        feed_tasks.get_order_task(task_id)
      end

      def get_order_report_tasks(params = {})
        feed_tasks.get_order_tasks(params.to_h.symbolize_keys.merge(feed_type: ORDER_REPORT_FEED_TYPE))
      end

      def get_order_report_result_file(task_id)
        result_file(task_id)
      end

      def submit_order_acknowledgement(file_path)
        upload_feed(file_path, ORDER_ACK_FEED_TYPE, client.configuration.order_ack_schema_version)
      end
    end
  end
end
