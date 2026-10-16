# frozen_string_literal: true

require 'securerandom'

module EbaySellerApi
  class MultipartBody
    attr_reader :content_type

    def initialize(file_path:, file_name:, content_type: 'application/octet-stream', fields: {})
      @file_path = file_path
      @file_name = File.basename(file_name.to_s).gsub(/["\r\n]/, '_')
      @file_content_type = content_type
      @fields = fields.stringify_keys
      @boundary = "----EbaySellerApi#{SecureRandom.hex(16)}"
      @content_type = "multipart/form-data; boundary=#{@boundary}"

      raise ArgumentError, 'file_name is required' if @file_name.blank?
    end

    def encode
      body = String.new(encoding: Encoding::BINARY)
      @fields.each { |name, value| body << part("Content-Disposition: form-data; name=\"#{name}\"", value.to_s.b) }
      body << part("Content-Disposition: form-data; name=\"file\"; filename=\"#{@file_name}\"\r\n" \
                   "Content-Type: #{@file_content_type}", File.binread(@file_path))
      body << "--#{@boundary}--\r\n".b
    end

    def log_summary
      @fields.merge('file' => "[multipart file #{@file_name}]")
    end

    # Keeps ActiveSupport's as_json/to_json (used by loggers) from dumping and reading the file.
    alias as_json log_summary

    private

    def part(headers, content)
      "--#{@boundary}\r\n#{headers}\r\n\r\n".b << content << "\r\n".b
    end
  end
end
