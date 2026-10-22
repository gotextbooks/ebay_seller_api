# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'tempfile'

RSpec.describe EbaySellerApi do
  before do
    described_class.configure do |config|
      config.client_id = 'test_client_id'
      config.client_secret = 'test_client_secret'
      config.ru_name = 'test_ru_name'
      config.environment = :sandbox
      config.refresh_token = 'test_refresh_token'
      config.listing_schema_version = '1235'
      config.order_report_schema_version = '1355'
      config.order_ack_schema_version = '1.0'
      config.logger = nil
    end
    described_class.reset!
    EbaySellerApi::OAuth2.tokens.clear

    stub_request(:post, %r{/identity/v1/oauth2/token}).to_return(
      status: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: {
        'access_token' => 'access_token',
        'expires_in' => 7200
      }.to_json
    )
  end

  def zip_file(files)
    Zip::OutputStream.write_buffer do |stream|
      files.each do |name, content|
        stream.put_next_entry(name)
        stream.write(content)
      end
    end.string
  end

  def inventory_tasks
    EbaySellerApi::Resources::Tasks.new(EbaySellerApi::Client.new, scope: EbaySellerApi::Resources::SELL_INVENTORY)
  end

  def ebay_result_file
    File.binread(File.expand_path('fixtures/ebay_result_file.zip', __dir__))
  end

  describe '.configure' do
    it 'uses the sandbox URLs for the sandbox environment' do
      expect(described_class.config.api_url).to eq('https://api.sandbox.ebay.com')
      expect(described_class.config.authorize_endpoint).to eq('https://auth.sandbox.ebay.com/oauth2/authorize')
    end

    it 'uses the production URLs for the production environment' do
      described_class.config.environment = :production

      expect(described_class.config.api_url).to eq('https://api.ebay.com')
      expect(described_class.config.authorize_endpoint).to eq('https://auth.ebay.com/oauth2/authorize')
    end
  end

  describe '.oauth' do
    let(:oauth) { described_class.oauth }
    let(:scope) { EbaySellerApi::Resources::SELL_INVENTORY }

    describe '#generate_auth_url' do
      it "returns eBay's consent page URL asking for every scope the gem uses" do
        url = oauth.generate_auth_url(state: 'xyz state')

        expect(url).to eq(
          'https://auth.sandbox.ebay.com/oauth2/authorize?client_id=test_client_id&redirect_uri=test_ru_name' \
          '&response_type=code&state=xyz%20state&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope' \
          '%20https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope%2Fsell.inventory' \
          '%20https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope%2Fsell.fulfillment'
        )
      end
    end

    describe '#obtain_token' do
      let!(:token_request) do
        stub_request(:post, %r{/identity/v1/oauth2/token}).to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: {
            'access_token' => 'user_access_token',
            'expires_in' => 7200,
            'refresh_token' => 'user_refresh_token'
          }.to_json
        )
      end

      it 'exchanges the code with basic auth and returns the tokens' do
        form = nil
        token_request.with do |req|
          form = URI.decode_www_form(req.body).to_h
        end

        tokens = oauth.obtain_token('the_code')

        expect(a_request(:post, %r{/identity/v1/oauth2/token}).with(basic_auth: %w[test_client_id test_client_secret]))
          .to have_been_made.once
        expect(form).to eq('grant_type' => 'authorization_code', 'code' => 'the_code', 'redirect_uri' => 'test_ru_name')
        expect(tokens['refresh_token']).to eq('user_refresh_token')
      end

      it 'refreshes with the obtained refresh token for the scope a request needs' do
        oauth.obtain_token('the_code')
        oauth.access_token(scope)

        expect(a_request(:post, %r{/identity/v1/oauth2/token})
          .with(body: { 'grant_type' => 'refresh_token', 'refresh_token' => 'user_refresh_token', 'scope' => scope }))
          .to have_been_made.once
      end
    end

    describe '#access_token' do
      it 'refreshes with the configured refresh token' do
        form = nil
        token_request = stub_request(:post, %r{/identity/v1/oauth2/token}).with do |req|
          form = URI.decode_www_form(req.body).to_h
        end.to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: { 'access_token' => 'access_token', 'expires_in' => 7200 }.to_json
        )

        expect(oauth.access_token(scope)).to eq('access_token')

        expect(token_request).to have_been_made.once
        expect(form).to eq('grant_type' => 'refresh_token', 'refresh_token' => 'test_refresh_token', 'scope' => scope)
      end

      it 'keeps the access token in memory until it expires' do
        oauth.access_token(scope)
        oauth.access_token(scope)
        travel_to(2.hours.from_now - 59.seconds) { oauth.access_token(scope) }

        expect(a_request(:post, %r{/identity/v1/oauth2/token})).to have_been_made.twice
      end

      it 'reuses a valid access token after reset!' do
        oauth.access_token(scope)
        described_class.reset!

        expect(described_class.oauth.access_token(scope)).to eq('access_token')
        expect(a_request(:post, %r{/identity/v1/oauth2/token})).to have_been_made.once
      end

      it 'refreshes after reset! once the access token has expired' do
        oauth.access_token(scope)
        described_class.reset!

        travel_to(2.hours.from_now) { described_class.oauth.access_token(scope) }

        expect(a_request(:post, %r{/identity/v1/oauth2/token})).to have_been_made.twice
      end

      it 'uses a new config.refresh_token after reset!' do
        oauth.access_token(scope)
        described_class.config.refresh_token = 'new_refresh_token'
        described_class.reset!

        described_class.oauth.access_token(scope)

        token_request = a_request(:post, %r{/identity/v1/oauth2/token})
        expect(token_request.with(body: hash_including('refresh_token' => 'new_refresh_token'))).to have_been_made.once
      end

      it 'requires a refresh token' do
        described_class.config.refresh_token = nil
        described_class.reset!

        expect do
          oauth.access_token(scope)
        end.to raise_error(ArgumentError, 'refresh_token is required to request an access token')
      end
    end
  end

  describe 'requests' do
    let!(:api_request) do
      stub_request(:get, %r{/sell/fulfillment/v1/order}).to_return(
        headers: { 'Content-Type' => 'application/json' },
        body: { 'orders' => [] }.to_json
      )
    end

    it 'sends the eBay headers and the access token' do
      headers = nil
      api_request.with do |req|
        headers = req.headers
      end

      described_class.orders.get_orders

      expect(headers).to include(
        'Authorization' => 'Bearer access_token',
        'X-Ebay-C-Marketplace-Id' => 'EBAY_US',
        'Accept-Language' => 'en-US',
        'Content-Language' => 'en-US'
      )
    end

    it 'returns the Faraday response with the JSON body parsed' do
      response = described_class.orders.get_orders

      expect(response).to be_a(Faraday::Response)
      expect(response.body).to eq('orders' => [])
    end

    it 'refreshes the access token and retries once when eBay rejects it' do
      stub_request(:post, %r{/identity/v1/oauth2/token}).to_return(
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { 'access_token' => 'old', 'expires_in' => 7200 }.to_json },
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { 'access_token' => 'new', 'expires_in' => 7200 }.to_json }
      )
      stub_request(:get, %r{/sell/fulfillment/v1/order}).with(headers: { 'Authorization' => 'Bearer old' }).to_return(
        status: 401,
        headers: { 'Content-Type' => 'application/json' },
        body: { 'errors' => [{ 'errorId' => 1001, 'message' => 'Invalid access token' }] }.to_json
      )

      described_class.orders.get_orders

      expect(api_request.with(headers: { 'Authorization' => 'Bearer new' })).to have_been_made.once
      expect(a_request(:post, %r{/identity/v1/oauth2/token})
        .with(body: hash_including('scope' => EbaySellerApi::Resources::SELL_FULFILLMENT))).to have_been_made.twice
    end

    it 'raises a status-based error when an error body is invalid JSON' do
      stub_request(:get, %r{/sell/fulfillment/v1/order}).to_return(
        status: 503,
        headers: { 'Content-Type' => 'application/json' },
        body: '{not json'
      )

      expect { described_class.orders.get_orders }.to raise_error(EbaySellerApi::ApiError::ServerError, /Invalid JSON/)
    end

    it 'raises NetworkError on timeouts' do
      stub_request(:get, %r{/sell/fulfillment/v1/order}).to_timeout

      expect { described_class.orders.get_orders }.to raise_error(EbaySellerApi::ApiError::NetworkError)
    end
  end

  describe 'logging' do
    let(:output) { StringIO.new }

    before do
      described_class.config.logger = Logger.new(output)
    end

    it 'filters tokens out of token requests and responses' do
      stub_request(:post, %r{/identity/v1/oauth2/token}).to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { 'access_token' => 'secret_access', 'refresh_token' => 'secret_refresh', 'expires_in' => 7200 }.to_json
      )

      described_class.oauth.refresh_user_access_token(EbaySellerApi::Resources::SELL_INVENTORY)

      expect(output.string).to include('"refresh_token" => "[FILTERED]"', '"access_token" => "[FILTERED]"')
      expect(output.string).not_to include('test_refresh_token', 'secret_access', 'secret_refresh')
    end

    it 'logs requests without the Authorization header' do
      stub_request(:get, %r{/sell/fulfillment/v1/order})

      described_class.orders.get_orders

      expect(output.string).to include('eBay API Request: GET https://api.sandbox.ebay.com/sell/fulfillment/v1/order')
      expect(output.string).not_to include('Bearer access_token')
    end

    it "logs response headers, such as a created task's Location" do
      stub_request(:post, %r{/sell/feed/v1/task$}).to_return(
        status: 202,
        headers: { 'Location' => 'https://api.sandbox.ebay.com/sell/feed/v1/task/task-1' }
      )

      inventory_tasks.create_task({ feedType: 'LMS_ADD_FIXED_PRICE_ITEM' })

      expect(output.string).to include('Response Headers:', 'https://api.sandbox.ebay.com/sell/feed/v1/task/task-1')
    end

    it 'logs file downloads by size only' do
      stub_request(:get, %r{/download_result_file}).to_return(
        headers: { 'Content-Type' => 'application/octet-stream' },
        body: ebay_result_file
      )

      inventory_tasks.get_result_file('task-1')

      expect(output.string).to include('Response Body: [binary 700 bytes]')
      expect(output.string).not_to include('VerifyAddFixedPriceItemRequest')
    end
  end

  describe 'OAuth scopes' do
    let(:inventory) { EbaySellerApi::Resources::SELL_INVENTORY }
    let(:fulfillment) { EbaySellerApi::Resources::SELL_FULFILLMENT }
    let(:xml_file) do
      Tempfile.new(['feed', '.xml']).tap do |tempfile|
        tempfile.write('<BulkDataExchangeRequests/>')
        tempfile.close
      end
    end

    before do
      stub_request(:any, %r{/sell/}).to_return(
        status: 202,
        headers: { 'Location' => 'https://api.sandbox.ebay.com/sell/feed/v1/task/task-1' }
      )
    end

    after { xml_file.unlink }

    def refreshed_scopes
      requests = WebMock::RequestRegistry.instance.requested_signatures.hash.flat_map { |request, count| [request] * count }
      requests.select { |request| request.uri.path.end_with?('/oauth2/token') }
              .map { |request| URI.decode_www_form(request.body).to_h['scope'] }
    end

    def bearer_tokens_for(path)
      requests = WebMock::RequestRegistry.instance.requested_signatures.hash.keys
      requests.select { |request| request.uri.path.include?(path) }.map { |request| request.headers['Authorization'] }
    end

    it 'refreshes only sell.inventory for listing feeds' do
      described_class.listings.submit_feed(xml_file.path, 'LMS_ADD_FIXED_PRICE_ITEM')
      described_class.listings.get_listing_status('task-1')

      expect(refreshed_scopes).to eq([inventory])
    end

    it 'refreshes only sell.fulfillment for orders and order feeds' do
      described_class.orders.get_orders
      described_class.orders.create_order_report_task
      described_class.orders.submit_order_acknowledgement(xml_file.path)

      expect(refreshed_scopes).to eq([fulfillment])
    end

    it 'keeps one access token per scope and sends the matching one with each request' do
      stub_request(:post, %r{/identity/v1/oauth2/token}).to_return do |request|
        scope = URI.decode_www_form(request.body).to_h['scope']
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { 'access_token' => "token for #{scope.split('.').last}", 'expires_in' => 7200 }.to_json }
      end

      described_class.listings.get_listing_status('task-1')
      described_class.orders.get_orders
      described_class.listings.get_listing_status('task-1')

      expect(bearer_tokens_for('/sell/feed/v1/task/')).to eq(['Bearer token for inventory'])
      expect(bearer_tokens_for('/sell/fulfillment/v1/order')).to eq(['Bearer token for fulfillment'])
    end

    it 'refreshes only the expired scope' do
      described_class.listings.get_listing_status('task-1')
      described_class.orders.get_orders

      travel_to(2.hours.from_now) { described_class.orders.get_orders }

      expect(refreshed_scopes).to contain_exactly(inventory, fulfillment, fulfillment)
    end

    it 'uses the fixed scope for order and inventory tasks' do
      described_class.tasks.get_order_tasks
      described_class.tasks.get_inventory_tasks

      expect(refreshed_scopes).to eq([fulfillment, inventory])
    end

    it 'requires a scope for task and schedule calls' do
      expect { described_class.tasks.get_tasks }
        .to raise_error(ArgumentError, 'An OAuth scope is required for GET /sell/feed/v1/task')
      expect(refreshed_scopes).to be_empty
    end
  end

  describe '.listings' do
    let(:listings) { described_class.listings }

    it 'returns a listings resource' do
      expect(listings).to be_a(EbaySellerApi::Resources::Listings)
    end

    describe '#submit_feed' do
      let(:xml) { %(<?xml version="1.0" encoding="UTF-8"?>\n<BulkDataExchangeRequests></BulkDataExchangeRequests>\n) }
      let(:file) do
        Tempfile.new(['AddFixedPriceItem', '.xml']).tap do |tempfile|
          tempfile.write(xml)
          tempfile.close
        end
      end
      let!(:create_task_request) do
        stub_request(:post, %r{/sell/feed/v1/task$}).to_return(
          status: 202,
          headers: { 'Location' => 'https://api.sandbox.ebay.com/sell/feed/v1/task/task-1' }
        )
      end
      let!(:upload_file_request) do
        stub_request(:post, %r{/sell/feed/v1/task/task-1/upload_file})
      end

      after { file.unlink }

      it 'creates a task with the feed type and the listing schema version' do
        body = nil
        create_task_request.with do |req|
          body = JSON.parse(req.body)
        end

        listings.submit_feed(file.path, 'LMS_ADD_FIXED_PRICE_ITEM')

        expect(create_task_request).to have_been_made.once
        expect(body).to eq('feedType' => 'LMS_ADD_FIXED_PRICE_ITEM', 'schemaVersion' => '1235')
      end

      it 'uploads the XML file as multipart form data' do
        request = nil
        upload_file_request.with do |req|
          request = req
        end
        file_name = File.basename(file.path)

        listings.submit_feed(file.path, 'LMS_ADD_FIXED_PRICE_ITEM')

        expect(upload_file_request).to have_been_made.once
        expect(request.headers['Content-Type']).to start_with('multipart/form-data; boundary=')
        expect(request.body.b).to include(
          %(name="fileName"\r\n\r\n#{file_name}\r\n),
          %(name="name"\r\n\r\nfile\r\n),
          %(name="type"\r\n\r\nform-data\r\n),
          %(name="file"; filename="#{file_name}"\r\nContent-Type: text/xml\r\n\r\n#{xml}\r\n)
        )
      end

      it 'returns the task ID' do
        expect(listings.submit_feed(file.path, 'LMS_ADD_FIXED_PRICE_ITEM')).to eq('task-1')
      end

      it 'raises without uploading when eBay sends no Location header' do
        stub_request(:post, %r{/sell/feed/v1/task$}).to_return(status: 202)

        expect { listings.submit_feed(file.path, 'LMS_ADD_FIXED_PRICE_ITEM') }
          .to raise_error(EbaySellerApi::Error, /missing location header/)
        expect(upload_file_request).not_to have_been_made
      end

      it 'raises the original error with the task ID when the upload fails' do
        stub_request(:post, %r{/sell/feed/v1/task/task-1/upload_file}).to_return(status: 500)

        expect { listings.submit_feed(file.path, 'LMS_ADD_FIXED_PRICE_ITEM') }
          .to raise_error(EbaySellerApi::ApiError::ServerError) { |error|
            expect(error).to be_a(EbaySellerApi::FeedUploadError)
            expect(error.task_id).to eq('task-1')
          }
      end

      it 'raises FeedFileError with the task ID when the file is missing' do
        expect { listings.submit_feed('/no/such/feed.xml', 'LMS_ADD_FIXED_PRICE_ITEM') }
          .to raise_error(EbaySellerApi::FeedFileError) { |error|
            expect(error).to be_a(EbaySellerApi::Error)
            expect(error).to be_a(EbaySellerApi::FeedUploadError)
            expect(error.task_id).to eq('task-1')
            expect(error.cause).to be_a(Errno::ENOENT)
          }
      end
    end

    describe '#get_listing_status' do
      let!(:api_request) do
        stub_request(:get, %r{/sell/feed/v1/task/task-1$}).to_return(
          headers: { 'Content-Type' => 'application/json' },
          body: { 'taskId' => 'task-1', 'status' => 'COMPLETED' }.to_json
        )
      end

      it 'gets the task' do
        response = listings.get_listing_status('task-1')

        expect(api_request).to have_been_made.once
        expect(response.body['status']).to eq('COMPLETED')
      end

      it 'requires a task ID' do
        expect { listings.get_listing_status('') }.to raise_error(ArgumentError, "task_id can't be blank")
      end
    end

    describe '#get_listing_result_file' do
      it "returns the XML inside eBay's result zip" do
        stub_request(:get, %r{/sell/feed/v1/task/task-1/download_result_file}).to_return(
          headers: { 'Content-Type' => 'application/octet-stream' },
          body: ebay_result_file
        )

        response = listings.get_listing_result_file('task-1')

        expect(response.body).to start_with('<?xml version="1.0" encoding="UTF-8"?>')
        expect(response.body).to include('<Ack>Failure</Ack>', '<ShortMessage>Specified SKU is in use</ShortMessage>')
        expect(response.body.encoding).to eq(Encoding::UTF_8)
      end

      it 'returns a body that is not a zip unchanged' do
        stub_request(:get, %r{/sell/feed/v1/task/task-1/download_result_file}).to_return(
          headers: { 'Content-Type' => 'text/xml' },
          body: '<BulkDataExchangeResponses/>'
        )

        expect(listings.get_listing_result_file('task-1').body).to eq('<BulkDataExchangeResponses/>')
      end

      it 'requires a task ID' do
        expect { listings.get_listing_result_file(nil) }.to raise_error(ArgumentError, "task_id can't be blank")
      end
    end
  end

  describe '.orders' do
    let(:orders) { described_class.orders }

    it 'returns an orders resource' do
      expect(orders).to be_a(EbaySellerApi::Resources::Orders)
    end

    describe '#get_orders' do
      let!(:api_request) do
        stub_request(:get, %r{/sell/fulfillment/v1/order}).to_return(
          headers: { 'Content-Type' => 'application/json' },
          body: { 'orders' => [] }.to_json
        )
      end

      it 'sends request with no query parameters' do
        uri = nil
        api_request.with do |req|
          uri = req.uri
        end

        orders.get_orders

        expect(api_request).to have_been_made.once

        params = uri.query_values
        expect(params).to be_nil
      end

      it 'sends the params as the query string' do
        uri = nil
        api_request.with do |req|
          uri = req.uri
        end

        orders.get_orders(filter: 'value', orderIds: '1,2', limit: 50, offset: 100, fieldGroups: 'TAX_BREAKDOWN')

        expect(api_request).to have_been_made.once
        expect(uri.query_values).to eq(
          'filter' => 'value', 'orderIds' => '1,2', 'limit' => '50', 'offset' => '100', 'fieldGroups' => 'TAX_BREAKDOWN'
        )
      end
    end

    describe '#get_order' do
      let!(:api_request) do
        stub_request(:get, %r{/sell/fulfillment/v1/order/12-34}).to_return(
          headers: { 'Content-Type' => 'application/json' },
          body: { 'orderId' => '12-34' }.to_json
        )
      end

      it 'sends request for the order' do
        response = orders.get_order('12-34')

        expect(api_request).to have_been_made.once
        expect(response.body['orderId']).to eq('12-34')
      end

      it 'sets the fieldGroups query parameter' do
        uri = nil
        api_request.with do |req|
          uri = req.uri
        end

        orders.get_order('12-34', fieldGroups: 'value')

        params = uri.query_values
        expect(params['fieldGroups']).to eq('value')
      end
    end

    describe '#create_order_report_task' do
      let!(:api_request) do
        stub_request(:post, %r{/sell/feed/v1/order_task$}).to_return(
          status: 202,
          headers: { 'Location' => 'https://api.sandbox.ebay.com/sell/feed/v1/order_task/task-7' }
        )
      end

      it 'creates an LMS_ORDER_REPORT task with the filter criteria' do
        body = nil
        api_request.with do |req|
          body = JSON.parse(req.body)
        end

        orders.create_order_report_task(
          creationDateRange: { from: '2026-10-06T00:00:00.000Z', to: '2026-10-16T00:00:00.000Z' },
          orderStatus: 'ACTIVE'
        )

        expect(api_request).to have_been_made.once
        expect(body).to eq(
          'feedType' => 'LMS_ORDER_REPORT',
          'schemaVersion' => '1355',
          'filterCriteria' => {
            'creationDateRange' => { 'from' => '2026-10-06T00:00:00.000Z', 'to' => '2026-10-16T00:00:00.000Z' },
            'orderStatus' => 'ACTIVE'
          }
        )
      end

      it 'leaves out filterCriteria when there are no filters' do
        body = nil
        api_request.with do |req|
          body = JSON.parse(req.body)
        end

        orders.create_order_report_task

        expect(body).to eq('feedType' => 'LMS_ORDER_REPORT', 'schemaVersion' => '1355')
      end

      it 'returns the task ID' do
        expect(orders.create_order_report_task).to eq('task-7')
      end
    end

    describe '#get_order_report_task' do
      let!(:api_request) do
        stub_request(:get, %r{/sell/feed/v1/order_task/task-7$}).to_return(
          headers: { 'Content-Type' => 'application/json' },
          body: { 'taskId' => 'task-7', 'status' => 'COMPLETED' }.to_json
        )
      end

      it 'gets the order task' do
        response = orders.get_order_report_task('task-7')

        expect(api_request).to have_been_made.once
        expect(response.body['status']).to eq('COMPLETED')
      end

      it 'requires a task ID' do
        expect { orders.get_order_report_task(' ') }.to raise_error(ArgumentError, "task_id can't be blank")
      end
    end

    describe '#get_order_report_tasks' do
      let!(:api_request) do
        stub_request(:get, %r{/sell/feed/v1/order_task}).to_return(
          headers: { 'Content-Type' => 'application/json' },
          body: { 'tasks' => [] }.to_json
        )
      end

      it 'sets the feed_type query parameter' do
        uri = nil
        api_request.with do |req|
          uri = req.uri
        end

        orders.get_order_report_tasks

        params = uri.query_values
        expect(params).to eq('feed_type' => 'LMS_ORDER_REPORT')
      end

      it 'sets the look_back_days query parameter' do
        uri = nil
        api_request.with do |req|
          uri = req.uri
        end

        orders.get_order_report_tasks(look_back_days: 'value')

        params = uri.query_values
        expect(params['look_back_days']).to eq('value')
      end

      it 'sends a single feed_type for string-keyed params' do
        uri = nil
        api_request.with do |req|
          uri = req.uri
        end

        orders.get_order_report_tasks('feed_type' => 'LMS_ACTIVE_INVENTORY_REPORT')

        expect(uri.query).to eq('feed_type=LMS_ORDER_REPORT')
      end
    end

    describe '#get_order_report_result_file' do
      it 'returns the XML inside the result zip' do
        xml = '<BulkDataExchangeResponses><OrderReportResponse/></BulkDataExchangeResponses>'
        stub_request(:get, %r{/sell/feed/v1/task/task-7/download_result_file}).to_return(
          headers: { 'Content-Type' => 'application/octet-stream' },
          body: zip_file('report.xml' => xml)
        )

        expect(orders.get_order_report_result_file('task-7').body).to eq(xml)
      end
    end

    describe '#submit_order_acknowledgement' do
      let(:file) do
        Tempfile.new(['OrderAck', '.xml']).tap do |tempfile|
          tempfile.write('<BulkDataExchangeRequests/>')
          tempfile.close
        end
      end
      let!(:create_task_request) do
        stub_request(:post, %r{/sell/feed/v1/task$}).to_return(
          status: 202,
          headers: { 'Location' => 'https://api.sandbox.ebay.com/sell/feed/v1/task/task-8' }
        )
      end
      let!(:upload_file_request) do
        stub_request(:post, %r{/sell/feed/v1/task/task-8/upload_file})
      end

      after { file.unlink }

      it 'uploads the file as an LMS_ORDER_ACK task' do
        body = nil
        create_task_request.with do |req|
          body = JSON.parse(req.body)
        end

        task_id = orders.submit_order_acknowledgement(file.path)

        expect(task_id).to eq('task-8')
        expect(body).to eq('feedType' => 'LMS_ORDER_ACK', 'schemaVersion' => '1.0')
        expect(upload_file_request).to have_been_made.once
      end
    end
  end

  describe '.tasks' do
    let(:tasks) { inventory_tasks }
    let(:feed) { 'https://api.sandbox.ebay.com/sell/feed/v1' }

    it 'returns a tasks resource' do
      expect(tasks).to be_a(EbaySellerApi::Resources::Tasks)
    end

    {
      get_order_tasks: '/order_task',
      get_inventory_tasks: '/inventory_task',
      get_schedules: '/schedule',
      get_schedule_templates: '/schedule_template',
      get_tasks: '/task'
    }.each do |method_name, path|
      describe "##{method_name}" do
        let!(:api_request) do
          stub_request(:get, "#{feed}#{path}").with(query: hash_including({}))
        end

        it 'sends request with no query parameters' do
          uri = nil
          api_request.with do |req|
            uri = req.uri
          end

          tasks.public_send(method_name)

          expect(api_request).to have_been_made.once

          params = uri.query_values
          expect(params).to be_nil
        end

        it 'sets the feed_type query parameter' do
          uri = nil
          api_request.with do |req|
            uri = req.uri
          end

          tasks.public_send(method_name, feed_type: 'value')

          params = uri.query_values
          expect(params['feed_type']).to eq('value')
        end
      end
    end

    {
      [:create_order_task, :post, '/order_task'] => [{ feedType: 'LMS_ORDER_REPORT' }],
      [:get_order_task, :get, '/order_task/task-1'] => ['task-1'],
      [:create_inventory_task, :post, '/inventory_task'] => [{ feedType: 'LMS_ACTIVE_INVENTORY_REPORT' }],
      [:get_inventory_task, :get, '/inventory_task/task-1'] => ['task-1'],
      [:create_schedule, :post, '/schedule'] => [{ feedType: 'LMS_ORDER_REPORT' }],
      [:get_schedule, :get, '/schedule/schedule-1'] => ['schedule-1'],
      [:update_schedule, :put, '/schedule/schedule-1'] => ['schedule-1', { scheduleName: 'name' }],
      [:delete_schedule, :delete, '/schedule/schedule-1'] => ['schedule-1'],
      [:get_schedule_template, :get, '/schedule_template/template-1'] => ['template-1'],
      [:create_task, :post, '/task'] => [{ feedType: 'LMS_ADD_FIXED_PRICE_ITEM' }],
      [:get_task, :get, '/task/task-1'] => ['task-1']
    }.each do |(method_name, verb, path), arguments|
      describe "##{method_name}" do
        it "sends #{verb.upcase} #{path}" do
          api_request = stub_request(verb, "#{feed}#{path}")

          tasks.public_send(method_name, *arguments)

          expect(api_request).to have_been_made.once
        end
      end
    end

    {
      get_result_file: '/task/task-1/download_result_file',
      get_input_file: '/task/task-1/download_input_file',
      get_latest_result_file: '/schedule/task-1/download_result_file'
    }.each do |method_name, path|
      describe "##{method_name}" do
        it 'returns the file as binary' do
          stub_request(:get, "#{feed}#{path}").to_return(
            headers: { 'Content-Type' => 'application/octet-stream' },
            body: ebay_result_file
          )

          body = tasks.public_send(method_name, 'task-1').body

          expect(body).to eq(ebay_result_file)
          expect(body.encoding).to eq(Encoding::BINARY)
        end
      end
    end

    describe '#upload_file' do
      let(:boundary) { '----EbaySellerApi00000000000000000000000000000000' }
      let(:xml) { %(<?xml version="1.0" encoding="UTF-8"?>\n<BulkDataExchangeRequests></BulkDataExchangeRequests>\n) }
      let(:xml_file) do
        Tempfile.new(['feed', '.xml']).tap do |tempfile|
          tempfile.write(xml)
          tempfile.close
        end
      end

      before do
        allow(SecureRandom).to receive(:hex).with(16).and_return('0' * 32)
      end

      after { xml_file.unlink }

      it 'sends exactly the multipart request eBay documents' do
        request = nil
        api_request = stub_request(:post, "#{feed}/task/task-1/upload_file").with do |req|
          request = req
        end
        file = EbaySellerApi::MultipartBody.new(
          file_path: xml_file.path,
          file_name: 'feed.xml',
          content_type: 'text/xml',
          fields: { fileName: 'feed.xml', name: 'file', type: 'form-data' }
        )

        tasks.upload_file('task-1', file)

        expect(api_request).to have_been_made.once
        expect(request.headers['Content-Type']).to eq("multipart/form-data; boundary=#{boundary}")
        expect(request.body.b).to eq(
          "--#{boundary}\r\n" \
          "Content-Disposition: form-data; name=\"fileName\"\r\n\r\nfeed.xml\r\n" \
          "--#{boundary}\r\n" \
          "Content-Disposition: form-data; name=\"name\"\r\n\r\nfile\r\n" \
          "--#{boundary}\r\n" \
          "Content-Disposition: form-data; name=\"type\"\r\n\r\nform-data\r\n" \
          "--#{boundary}\r\n" \
          "Content-Disposition: form-data; name=\"file\"; filename=\"feed.xml\"\r\n" \
          "Content-Type: text/xml\r\n" \
          "\r\n" \
          "#{xml}\r\n" \
          "--#{boundary}--\r\n".b
        )
      end
    end
  end
end
