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

result = client.evaluate("new-dashboard", {
  "user_id" => "user-123",
  "country" => "TR"
})

puts result.enabled?   # true
puts result.value_type # "string"
puts result.value      # "dark_mode"
puts result.reason     # "rule_match"
```

## EvaluateResult

`evaluate` returns an `EvaluateResult` object:

```ruby
result.flag_key    # String  — flag identifier
result.enabled     # Boolean — whether the flag is on
result.enabled?    # Boolean — alias for enabled
result.value_type  # String  — "boolean" | "string" | "number" | "json"
result.value       # mixed   — the resolved value
result.reason      # String  — e.g. "rule_match", "default"
```

## Notes

- `api_key` must be an environment API key, not a user JWT.
- Requests are sent to `POST /api/v1/evaluate` with the `X-API-Key` header.
- The cache key includes the full evaluation context.
- The client retries `429` and `5xx`, but stops immediately on `401`/`403`/`404`.
