# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbaySellerApi::ApiError do
  def response_for(body, status: 400)
    Faraday::Response.new(status:, body:, response_headers: {}, reason_phrase: 'Bad Request')
  end

  describe '.from_response' do
    it do
      response = response_for({
                                'errors' => [{
                                  'errorId' => 160_017,
                                  'domain' => 'API_FEED',
                                  'category' => 'REQUEST',
                                  'message' => 'message',
                                  'longMessage' => 'description'
                                }]
                              })

      error = described_class.from_response(response)

      expect(error.message).to eq('message')
      expect(error.description).to eq('description')
      expect(error.error_code).to eq(160_017)
    end

    it do
      response = response_for({
        'errors' => [{
          'message' => 'message'
        }, {
          'message' => 'another message'
        }]
      }.to_json)

      error = described_class.from_response(response)

      expect(error.message).to eq('message')
      expect(error.first_error).to eq('message' => 'message')
    end

    it do
      response = response_for({
                                'error' => 'message',
                                'error_description' => 'description'
                              })

      error = described_class.from_response(response)

      expect(error.message).to eq('message')
      expect(error.description).to eq('description')
    end

    it do
      response = response_for({
                                'errors' => [{
                                  'message' => 'message'
                                }]
                              })

      error = described_class.from_response(response)

      expect(error.description).to eq('Bad Request')
    end

    it do
      error = described_class.from_response(response_for('message', status: 503))

      expect(error.message).to eq('message')
    end

    it do
      error = described_class.from_response(response_for({ 'errors' => [] }))

      expect(error.message).to eq('Unknown eBay API Error')
    end

    it do
      error = described_class.from_response(response_for({ 'something' => 'else' }))

      expect(error.message).to eq('Unknown eBay API Error')
    end

    it do
      error = described_class.from_response(response_for('', status: 500))

      expect(error.message).to eq('eBay API Error')
      expect(error.description).to eq('No data is set in response result.')
    end

    it do
      body = { 'errors' => [{ 'message' => 'message' }] }
      response = Faraday::Response.new(status: 400, body:, response_headers: { 'x-ebay-c-request-id' => 'id' })

      error = described_class.from_response(response)

      expect(error.status_code).to eq(400)
      expect(error.response_body).to eq(body)
      expect(error.response_headers).to eq('x-ebay-c-request-id' => 'id')
    end
  end

  describe 'error classes' do
    it do
      error = described_class.from_response(response_for({ 'error' => 'invalid_grant' }))

      expect(error).to be_a(described_class::InvalidGrant)
    end

    it do
      error = described_class.from_response(response_for({ 'error' => 'invalid_scope' }))

      expect(error).to be_a(described_class::InvalidScope)
    end

    it do
      error = described_class.from_response(
        response_for({ 'errors' => [{ 'errorId' => 1001, 'message' => 'Invalid access token' }] }, status: 401)
      )

      expect(error).to be_a(described_class::InvalidAccessToken)
      expect(error).to be_a(described_class::AuthenticationError)
    end

    it do
      error = described_class.from_response(response_for({ 'errors' => [{ 'errorId' => 160_024 }] }, status: 409))

      expect(error).to be_a(described_class::RateLimitError)
    end

    it do
      error = described_class.from_response(response_for({ 'errors' => [{ 'errorId' => 160_025 }] }, status: 409))

      expect(error).to be_a(described_class::RateLimitError)
    end

    it do
      error = described_class.from_response(response_for({ 'errors' => [{ 'errorId' => 160_035 }] }, status: 409))

      expect(error.class).to eq(described_class)
    end

    {
      400 => described_class::ValidationError,
      422 => described_class::ValidationError,
      401 => described_class::AuthenticationError,
      403 => described_class::AuthorizationError,
      404 => described_class::NotFoundError,
      429 => described_class::RateLimitError,
      500 => described_class::ServerError,
      503 => described_class::ServerError,
      418 => described_class
    }.each do |status, error_class|
      it "maps status #{status} to #{error_class.name.demodulize}" do
        error = described_class.from_response(response_for({ 'errors' => [{ 'message' => 'message' }] }, status:))

        expect(error.class).to eq(error_class)
      end
    end
  end
end
