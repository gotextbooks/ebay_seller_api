# eBay Seller API Ruby SDK

A Ruby SDK for eBay's Sell APIs: bulk listing uploads as XML feeds, orders, order reports and Feed tasks and notifications.

## Features

- **Authentication**: OAuth2 consent flow and automatic access token refresh
- **Listings**: Submit LMS XML listing feeds (add, revise, verify) and download their results
- **Orders**: Get orders, request order reports and send order acknowledgements
- **Feed tasks**: Get and create order and inventory tasks
- **Notifications**: Subscribe to topics so eBay sends notifications to our registered endpoints
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
# Also ask for the scopes of the Notification topics we will subscribe to (read from eBay's getTopic)
url = EbaySellerApi.oauth.generate_auth_url(topics: ['ORDER_CONFIRMATION'], state: "csrf_token")
tokens = EbaySellerApi.oauth.obtain_token(params[:code])
tokens["refresh_token"] # store it and set config.refresh_token
```

The consent page asks for every scope the gem's resources need (`CONSENT_SCOPES`), plus the `authorizationScopes`
of each topic passed in `topics:`, so there is no scope to configure. Every scope must also be listed under your app's
OAuth scopes in the eBay Developer Portal. Each request uses an access
token with only its own scope (`sell.inventory` for listings, `sell.fulfillment` for orders), refreshed when it expires.

Some endpoints act for the application rather than the seller, such as the Notification API's config, destinations 
and public keys. For those, the gem requests an application access token (client credentials grant) with your 
'client_id' and 'client_secret', keeps it in memory and requests a new one when it expires. It needs no refresh 
token.

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

### Notifications
eBay pushes notifications, such as 'ORDER_CONFIRMATION', to an HTTPS endpoint that we registered as a destination.
Config, destination, topic and public key calls use the application access token. Subscription calls use the seller's 
token, which needs the `commerce.notification.subscription` scope.

`create_subscription` first calls `get_topic` for the `topicId` and adds the topic's `authorizationScopes` to that
token. For example, `ORDER_CONFIRMATION` also needs `sell.fulfillment` and `sell.fulfillment.readonly`. The seller must
have granted these scopes, so pass the topic to `generate_auth_url(topics: [...])` before they consent.

`Create`, `update` and `test` calls return an empty body. `Create` calls return the new ID in the `location` header;
then `EbaySellerApi::Resources::Notifications.created_id(response` reads it.

```ruby
notifications = EbaySellerApi.notifications

# Set the email eBay sends Notification API alerts to
notifications.update_config(alertEmail: 'test@example.com')

# Register your endpoint. eBay calls it with a challenge_code that it must answer first.
# The verificationToken is used to verify the request came from eBay. The passed verificationToken should be saved or cached to be used for the challenge_code verification.
response = notifications.create_destination({
                                              name: 'order-confirmation-destination',
                                              status: 'ENABLED',
                                              deliveryConfig: {
                                                endpoint: "https://example.com/ebay-seller-api/notifications",
                                                verificationToken: SecureRandom.uuid
                                              }
                                            })
destination_id = EbaySellerApi::Resources::Notifications.created_id(response)

# See a topic's details, including the authorizationScopes needed to subscribe to it
notifications.get_topic('ORDER_CONFIRMATION')

# Subscribe the destination to a topic
response = notifications.create_subscription({
                                               topicId: 'ORDER_CONFIRMATION',
                                               status: 'ENABLED',
                                               destinationId: destination_id,
                                               payload: {
                                                 format: 'JSON',
                                                 schemaVersion: '1.0',
                                                 deliveryProtocol: 'HTTPS'
                                               }
                                             })
subscription_id = EbaySellerApi::Resources::Notifications.created_id(response)

# Check on them later
notifications.get_subscription(subscription_id)
notifications.get_destination(destination_id)

# Ask eBay to send a test notification to the destination
notifications.test_subscription(subscription_id)
```

Each notification has an `X-EBAY-SIGNATURE` header: Base64-encoded JSON with the ID of the key that signed it. Get 
that key to verify the signature.

```ruby
signature = JSON.parse(request.headers['X-EBAY-SIGNATURE'].unpack1("m"))
key = EbaySellerApi.notifications.get_public_key(signature["kid"]).body
key["key"]       # the public key (PEM)
key["algorithm"] # "ECDSA"
key["digest"]    # "SHA1"
```

eBay asks you to cache the key, for about an hour, rather than fetch it for every notification.

The ID arguments are required: `get_destination(nil)` raises `ArgumentError` before calling eBay.

### Feed Tasks

```ruby
EbaySellerApi.tasks.get_order_tasks(feed_type: "LMS_ORDER_REPORT")
EbaySellerApi.tasks.get_inventory_task("task-1")
```

Listing and order feed tasks go through `EbaySellerApi.listings` and `EbaySellerApi.orders`.

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
