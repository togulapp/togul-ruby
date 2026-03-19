# Togul Ruby SDK

Ruby client for evaluating Togul feature flags with local TTL caching and fallback behavior.

## Install

```bash
gem install togul-flags
```

## Usage

```ruby
require "togul"

client = Togul::Client.new(Togul::Config.new(
  base_url: "http://localhost:8080",
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

## Notes

- `api_key` must be an environment API key, not a user JWT.
- Requests are sent to `POST /api/v1/evaluate` with the `X-API-Key` header.
- The cache key includes the full evaluation context.
- The client retries `429` and `5xx`, but stops immediately on `401`/`403`/`404`.
