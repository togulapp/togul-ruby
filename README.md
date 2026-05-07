# Togul Ruby SDK

Ruby client for evaluating Togul feature flags with local TTL caching and fallback behavior.

## Install

```bash
gem install togul
```

Or in your Gemfile:

```ruby
gem 'togul', '~> 2.4'
```

## Usage

### Boolean Flag

```ruby
require "togul"

client = Togul::Client.new(Togul::Config.new(
  environment: "production",
  api_key: "your-environment-api-key",
  timeout: 5,
  cache_ttl: 30,
  fallback_mode: :fail_closed,
  retry_count: 2
))

enabled = client.enabled?("new-dashboard", {
  "user_id" => "user-123",
  "country" => "TR"
})
```

### Multi-Variant Flag

Use `evaluate` to get typed values from flags with multiple variants:

```ruby
result = client.evaluate("checkout-theme", {
  "user_id" => "user-123"
})

result.enabled?                     # => true
result.string_value("default")      # => "dark"
result.bool_value(false)            # => false (wrong type, returns fallback)
result.number_value(0.0)            # => 0.0   (wrong type, returns fallback)
result.json_value(nil)              # => nil   (wrong type, returns fallback)
```

`EvaluateResult` attributes: `flag_key`, `enabled`, `value_type`, `reason`

## Notes

- `api_key` must be an environment API key, not a user JWT.
- Requests are sent to `POST /api/v1/evaluate` with the `X-API-Key` header.
- The cache key includes the full evaluation context.
- The client retries `429` and `5xx`, but stops immediately on `401`/`403`/`404`.
