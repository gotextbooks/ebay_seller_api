# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbaySellerApi::Resources::Orders do
  def scopes
    %w[
      https://api.ebay.com/oauth/api_scope/sell.inventory
      https://api.ebay.com/oauth/api_scope/sell.fulfillment
      https://api.ebay.com/oauth/api_scope/commerce.notification.subscription
    ]
  end

  def orders
    EbaySellerApi.orders
  end

  before do
    EbaySellerApi.configure do |config|
      config.client_id = 'test_client_id'
      config.client_secret = 'test_client_secret'
      config.ru_name = 'test_ru_name'
      config.scopes = scopes
      config.environment = :sandbox
      config.refresh_token = 'test_refresh_token'
      config.listing_schema_version = '1235'
      config.order_report_schema_version = '1355'
      config.order_ack_schema_version = '1.0'
      config.logger = nil
    end
    EbaySellerApi.reset!
    EbaySellerApi::OAuth2.tokens.clear

    stub_request(:post, %r{/identity/v1/oauth2/token}).to_return(
      status: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: { 'access_token' => 'access_token', 'expires_in' => 7200 }.to_json
    )
  end

  describe 'apiz host' do
    it 'uses the sandbox apiz URL for the sandbox environment' do
      expect(EbaySellerApi.config.apiz_url).to eq('https://apiz.sandbox.ebay.com')
    end

    it 'uses the production apiz URL for the production environment' do
      EbaySellerApi.config.environment = :production

      expect(EbaySellerApi.config.apiz_url).to eq('https://apiz.ebay.com')
    end

    it 'sends a resource request to apiz when asked, keeping the base path and query' do
      resource_class = Class.new(EbaySellerApi::Resources::Base) do
        const_set(:BASE_PATH, '/sell/fulfillment/v1')

        def ping(params)
          get('/ping', query: params, apiz: true)
        end
      end
      request = stub_request(:get, 'https://apiz.sandbox.ebay.com/sell/fulfillment/v1/ping')
                .with(query: { 'limit' => '1' }, headers: { 'Authorization' => 'Bearer access_token' })
                .to_return(status: 200)

      resource_class.new(EbaySellerApi::Client.new).ping(limit: 1)

      expect(request).to have_been_made.once
    end

    it 'keeps sending existing order calls to the api host' do
      request = stub_request(:get, 'https://api.sandbox.ebay.com/sell/fulfillment/v1/order/ORDER-1')
                .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')

      orders.get_order('ORDER-1')

      expect(request).to have_been_made.once
    end
  end

  describe '#create_order_report_task' do
    it 'raises the task ID error when eBay sends no Location header' do
      stub_request(:post, 'https://api.sandbox.ebay.com/sell/feed/v1/order_task').to_return(status: 201)

      expect { orders.create_order_report_task }
        .to raise_error(EbaySellerApi::Error, 'eBay returned no task ID (missing location header)')
    end
  end

  describe 'shipping fulfillments' do
    let(:base_url) { 'https://apiz.sandbox.ebay.com/sell/fulfillment/v1' }
    let(:fulfillments_url) { "#{base_url}/order/ORDER-1/shipping_fulfillment" }
    let(:body) do
      {
        lineItems: [{ lineItemId: '10000000000001', quantity: 1 }],
        shippedDate: '2026-11-20T18:00:00.000Z',
        shippingCarrierCode: 'USPS',
        trackingNumber: '1Z999'
      }
    end

    def created(location)
      { status: 201, headers: { 'Location' => location }, body: '' }
    end

    def json(status, data)
      { status:, headers: { 'Content-Type' => 'application/json' }, body: data.to_json }
    end

    describe '#create_shipping_fulfillment' do
      it 'posts the fulfillment to apiz and returns the fulfillment ID from the Location header' do
        request = stub_request(:post, fulfillments_url)
                  .with(body:, headers: { 'Content-Type' => 'application/json' })
                  .to_return(created("#{fulfillments_url}/1Z999"))

        expect(orders.create_shipping_fulfillment('ORDER-1', body)).to eq('1Z999')
        expect(request).to have_been_made.once
      end

      it 'raises when eBay sends no Location header' do
        stub_request(:post, fulfillments_url).to_return(status: 201)

        expect { orders.create_shipping_fulfillment('ORDER-1', body) }
          .to raise_error(EbaySellerApi::Error, 'eBay returned no fulfillment ID (missing location header)')
      end

      it 'raises a validation error with the eBay error ID' do
        stub_request(:post, fulfillments_url).to_return(
          json(400, errors: [{ errorId: 34_600, domain: 'API_FULFILLMENT', category: 'REQUEST',
                               message: 'Invalid tracking number.' }])
        )

        expect { orders.create_shipping_fulfillment('ORDER-1', body) }.to raise_error(
          an_instance_of(EbaySellerApi::ApiError::ValidationError)
            .and(having_attributes(status_code: 400, error_code: 34_600))
        )
      end
    end

    describe '#create_additional_shipping_fulfillment' do
      it 'posts the fulfillment to create_additional on apiz and returns the fulfillment ID' do
        request = stub_request(:post, "#{fulfillments_url}/create_additional")
                  .with(body:)
                  .to_return(created("#{fulfillments_url}/1Z998"))

        expect(orders.create_additional_shipping_fulfillment('ORDER-1', body)).to eq('1Z998')
        expect(request).to have_been_made.once
      end

      it 'raises when eBay sends no Location header' do
        stub_request(:post, "#{fulfillments_url}/create_additional").to_return(status: 201)

        expect { orders.create_additional_shipping_fulfillment('ORDER-1', body) }
          .to raise_error(EbaySellerApi::Error, 'eBay returned no fulfillment ID (missing location header)')
      end
    end

    describe '#get_shipping_fulfillments' do
      let(:fulfillments) { { 'fulfillments' => [{ 'fulfillmentId' => '1Z999' }], 'total' => 1 } }

      it 'passes query params through and returns the parsed body' do
        stub_request(:get, fulfillments_url)
          .with(query: { 'limit' => '10', 'offset' => '0' })
          .to_return(json(200, fulfillments))

        expect(orders.get_shipping_fulfillments('ORDER-1', limit: 10, offset: 0).body).to eq(fulfillments)
      end

      it 'sends no query string without params' do
        request = stub_request(:get, fulfillments_url).to_return(json(200, fulfillments))

        orders.get_shipping_fulfillments('ORDER-1')

        expect(request).to have_been_made.once
      end
    end

    describe '#get_shipping_fulfillment' do
      it 'encodes both IDs in the apiz path' do
        request = stub_request(:get, "#{base_url}/order/12-345%2F6/shipping_fulfillment/FF%201")
                  .to_return(json(200, 'fulfillmentId' => 'FF 1'))

        expect(orders.get_shipping_fulfillment('12-345/6', 'FF 1').body).to eq('fulfillmentId' => 'FF 1')
        expect(request).to have_been_made.once
      end
    end

    describe 'blank IDs' do
      [nil, '', ' '].each do |blank|
        it "rejects order_id #{blank.inspect} on every method without sending a request" do
          expect { orders.create_shipping_fulfillment(blank, body) }
            .to raise_error(ArgumentError, 'Missing required argument: order_id')
          expect { orders.create_additional_shipping_fulfillment(blank, body) }
            .to raise_error(ArgumentError, 'Missing required argument: order_id')
          expect { orders.get_shipping_fulfillments(blank) }
            .to raise_error(ArgumentError, 'Missing required argument: order_id')
          expect { orders.get_shipping_fulfillment(blank, '1Z999') }
            .to raise_error(ArgumentError, 'Missing required argument: order_id')
          expect(a_request(:any, /shipping_fulfillment/)).not_to have_been_made
        end

        it "rejects fulfillment_id #{blank.inspect} without sending a request" do
          expect { orders.get_shipping_fulfillment('ORDER-1', blank) }
            .to raise_error(ArgumentError, 'Missing required argument: fulfillment_id')
          expect(a_request(:any, /shipping_fulfillment/)).not_to have_been_made
        end
      end
    end
  end
end
