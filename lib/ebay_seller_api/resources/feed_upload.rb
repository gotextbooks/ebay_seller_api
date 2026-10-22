# frozen_string_literal: true

require 'stringio'
require 'zip'

module EbaySellerApi
  module Resources
    module FeedUpload
      ZIP_SIGNATURE = "PK\x03\x04".b

      private

      def upload_feed(file_path, feed_type, schema_version)
        task_id = task_id_from(feed_tasks.create_task({ feedType: feed_type, schemaVersion: schema_version }))

        begin
          feed_tasks.upload_file(task_id, feed_file(file_path))
        rescue Error => e
          e.extend(FeedUploadError).task_id = task_id
          raise
        rescue StandardError => e
          raise FeedFileError.new("Uploading the file to task #{task_id} failed: #{e.message}", task_id:)
        end

        task_id
      end

      def result_file(task_id)
        require_task_id!(task_id)

        response = feed_tasks.get_result_file(task_id)
        response.env.body = unzip(response.body) if response.body.to_s.byteslice(0, 4) == ZIP_SIGNATURE
        response
      end

      def unzip(zip)
        xml = nil
        Zip::File.open_buffer(StringIO.new(zip)) { |archive| xml = archive.entries.first.get_input_stream.read }
        xml.force_encoding(Encoding::UTF_8)
      end

      def feed_tasks
        @feed_tasks ||= Tasks.new(client, scope:)
      end

      def feed_file(file_path)
        file_name = File.basename(file_path)

        MultipartBody.new(
          file_path:,
          file_name:,
          content_type: 'text/xml',
          fields: { fileName: file_name, name: 'file', type: 'form-data' }
        )
      end

      def task_id_from(response)
        task_id = response.headers['location'].to_s.split('/').last
        raise Error, 'eBay returned no task ID (missing location header)' if task_id.blank?

        task_id
      end

      def require_task_id!(task_id)
        raise ArgumentError, "task_id can't be blank" if task_id.blank?
      end
    end
  end
end
