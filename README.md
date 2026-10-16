# eBay Seller API Ruby SDK

A Ruby SDK for eBay's Sell APIs: bulk listing uploads as XML feeds, orders, order reports and Feed tasks.

## Features

- **Authentication**: OAuth2 consent flow and automatic access token refresh
- **Listings**: Submit LMS XML listing feeds (add, revise, verify) and download their results
- **Orders**: Get orders, request order reports and send order acknowledgements
- **Feed tasks**: Create tasks, upload files, check status and download results
- **Error handling**: Exception classes for eBay's error responses
- **Logging**: Request/response logging with tokens filtered out

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ebay_seller_api', git: 'https://github.com/gotextbooks/ebay_seller_api.git'
```

And then execute:

```bash
bundle install
```

## Configuration

```ruby
EbaySellerApi.configure do |config|
  config.client_id = "your_client_id"
  config.client_secret = "your_client_secret"
  config.ru_name = "your_ru_name"           # for the consent flow
  config.refresh_token = "seller_refresh_token"
  config.environment = :sandbox             # or :production
  config.scope = %w[
    https://api.ebay.com/oauth/api_scope/sell.inventory
    https://api.ebay.com/oauth/api_scope/sell.fulfillment
  ]
  config.logger = Rails.logger              # Optional
end
```

Optional settings: `marketplace_id` (`EBAY_US`), `content_language` and `accept_language` (`en-US`), `timeout`,
`open_timeout`, and the Feed task schema versions `listing_schema_version` (`1487`, must match `<Version>` in the XML), `order_report_schema_version`
(`1355`) and `order_ack_schema_version` (`1.0`).

## Authentication

Send the seller to eBay's consent page, then exchange the code eBay redirects back with for a refresh token:

```ruby
url = EbaySellerApi.oauth.generate_auth_url(state: "csrf_token")
tokens = EbaySellerApi.oauth.obtain_token(params[:code])
tokens["refresh_token"] # store it and set config.refresh_token
```

The gem exchanges the refresh token for an access token on the first call, keeps it in memory and refreshes it when
it expires.

## Usage

Every method returns the `Faraday::Response`, with JSON bodies parsed into a Hash.

### Listings

```ruby
# Submit an XML feed (returns the task ID)
task_id = EbaySellerApi.listings.submit_feed("/path/to/AddFixedPriceItem.xml", "LMS_ADD_FIXED_PRICE_ITEM")

# Revise price and quantity
EbaySellerApi.listings.submit_feed("/path/to/ReviseInventoryStatus.xml", "LMS_REVISE_INVENTORY_STATUS")

# Check the task status
status = EbaySellerApi.listings.get_listing_status(task_id).body["status"]

# Get the result file's XML once the task is COMPLETED
xml = EbaySellerApi.listings.get_listing_result_file(task_id).body
```

### Orders

```ruby
# Get orders
orders = EbaySellerApi.orders.get_orders(filter: "orderfulfillmentstatus:{NOT_STARTED|IN_PROGRESS}", limit: 50)

# Get a specific order
order = EbaySellerApi.orders.get_order("ORDER123")

# Request an order report (returns the task ID)
task_id = EbaySellerApi.orders.create_order_report_task(
  creationDateRange: { from: "2026-10-14T00:00:00.000Z", to: "2026-10-16T00:00:00.000Z" }
)
status = EbaySellerApi.orders.get_order_report_task(task_id).body["status"]
report = EbaySellerApi.orders.get_order_report_result_file(task_id).body

# Acknowledge orders with an OrderAck XML file (returns the task ID)
EbaySellerApi.orders.submit_order_acknowledgement("/path/to/OrderAck.xml")
```

### Feed Tasks

```ruby
# List tasks
tasks = EbaySellerApi.tasks.get_tasks(feed_type: "LMS_ADD_FIXED_PRICE_ITEM", look_back_days: 7)

# Get a task
task = EbaySellerApi.tasks.get_task("task-1")

# Download a task's raw result file (zip)
zip = EbaySellerApi.tasks.get_result_file("task-1").body
```

## Error Handling

```ruby
begin
  EbaySellerApi.listings.submit_feed("/path/to/feed.xml", "LMS_ADD_FIXED_PRICE_ITEM")
rescue EbaySellerApi::ApiError::InvalidGrant => e
  puts "The seller must consent again: #{e.message}"
rescue EbaySellerApi::ApiError::ValidationError => e
  puts "Validation error: #{e.message}"
rescue EbaySellerApi::ApiError::RateLimitError => e
  puts "Rate limit exceeded: #{e.message}"
rescue EbaySellerApi::ApiError::NotFoundError => e
  puts "Resource not found: #{e.message}"
rescue EbaySellerApi::ApiError::ServerError => e
  puts "Server error: #{e.message}"
rescue EbaySellerApi::ApiError::NetworkError => e
  puts "Network error: #{e.message}"
end
```

If a feed task is created but its file upload fails, the error has the `task_id`, so the upload can be retried
against the same task. eBay errors keep their class (e.g. `ApiError::RateLimitError`); other failures, such as a
missing file, raise `EbaySellerApi::FeedFileError` with the original error as `cause`. Both can be rescued as
`EbaySellerApi::FeedUploadError`:

```ruby
begin
  EbaySellerApi.listings.submit_feed("/path/to/feed.xml", "LMS_ADD_FIXED_PRICE_ITEM")
rescue EbaySellerApi::FeedUploadError => e
  puts "Upload to task #{e.task_id} failed: #{e.message}"
end
```

## Logging

```ruby
EbaySellerApi.configure do |config|
  config.logger = Rails.logger
end
```

This logs every request and response. Tokens and the Authorization header are never logged, and file downloads are
logged by size only.

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rspec` to run the
tests. You can also run `bin/console` for an interactive prompt.

## License

The gem is available under the terms of the [MIT License](LICENSE.txt).
