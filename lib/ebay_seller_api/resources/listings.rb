# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Listings < Base
      include FeedUpload

      # can be used for both submitting listing and revising inventory status (quantity, price)
      def submit_feed(file_path, feed_type)
        upload_feed(file_path, feed_type, client.configuration.listing_schema_version)
      end

      def get_listing_status(task_id)
        require_task_id!(task_id)

        feed_tasks.get_task(task_id)
      end

      def get_listing_result_file(task_id)
        result_file(task_id)
      end
    end
  end
end
