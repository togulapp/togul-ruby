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

## Streaming

```ruby
# Register a listener, then start the background SSE thread.
client.on_cache_invalidated { |flag_key| puts "invalidated: #{flag_key}" }
client.start_stream
```

`start_stream` spawns a background thread that connects to `GET /api/v1/stream` and invalidates the local cache when flag-change events arrive. It reconnects automatically with exponential backoff on transient failures, and stops only on `401`/`403`. Listeners fire for stream events and for manual `invalidate_cache` / `invalidate_flag` calls alike.

## OpenFeature

`Togul::OpenFeature::Provider` plugs Togul into the [OpenFeature](https://openfeature.dev) Ruby SDK, so application code can depend on the vendor-neutral API instead of `Togul::Client`. It is not loaded by `require "togul"`; add the SDK and require it explicitly. Tested with `openfeature-sdk` 0.5.1 (Ruby 3.1–3.3); 0.6.x needs Ruby ≥ 3.4 and is not yet covered by the test suite.

```ruby
gem "openfeature-sdk"
```

```ruby
require "togul/open_feature"

togul = Togul::Client.new(Togul::Config.new(environment: "production", api_key: "your-environment-api-key"))
togul.start_stream # optional: SSE cache invalidation

OpenFeature::SDK.configure do |config|
  config.set_provider_and_wait(Togul::OpenFeature::Provider.new(togul))
end

client = OpenFeature::SDK.build_client
context = OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-42", country: "TR")

client.fetch_boolean_value(flag_key: "new-dashboard", default_value: false, evaluation_context: context)
client.fetch_string_value(flag_key: "theme", default_value: "light", evaluation_context: context)
client.fetch_integer_value(flag_key: "max-items", default_value: 10, evaluation_context: context)
client.fetch_object_value(flag_key: "limits", default_value: {}, evaluation_context: context)
```

The provider only adapts `Togul::Client#evaluate`; caching, retries and SSE invalidation are unchanged, and every invalidation is re-emitted as `PROVIDER_CONFIGURATION_CHANGED`. Context values are flattened to strings (hashes and arrays JSON-encoded, times ISO 8601) and the targeting key is sent as `user_id` unless `user_id` is set; `targeting_key_attribute: "account_id"` changes that.

| Togul | OpenFeature |
|---|---|
| `reason: rule_match` | `TARGETING_MATCH` |
| `reason: default` | `DEFAULT` |
| `enabled: false` | caller's default value, reason `DISABLED` |
| `404 evaluate.flag_not_found` | caller's default, `FLAG_NOT_FOUND` |
| value does not fit the requested type (incl. a fractional number for integers) | caller's default, `TYPE_MISMATCH` |
| any other error | caller's default, `GENERAL` |

## Notes

- `api_key` must be an environment API key, not a user JWT.
- Requests are sent to `POST /api/v1/evaluate` with the `X-API-Key` header.
- The cache key includes the full evaluation context.
- The client retries `429` and `5xx`, but stops immediately on `401`/`403`/`404`.
