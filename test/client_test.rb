# frozen_string_literal: true

require_relative 'test_helper'

class TogulClientTest < Minitest::Test
  # ── evaluate: value types ──────────────────────────────────────────────

  def test_evaluate_boolean_flag
    http = FakeHTTP.new([eval_response('value_type' => 'boolean', 'value' => true)])
    result = nil
    Net::HTTP.stub(:new, http) do
      result = Togul::Client.new(make_config).evaluate('test-flag', { 'user_id' => 'u1' })
    end

    assert_instance_of Togul::EvaluateResult, result
    assert_equal 'test-flag', result.flag_key
    assert_equal true,        result.enabled
    assert_equal 'boolean',   result.value_type
    assert_equal true,        result.value
    assert_equal 'rule_match', result.reason
  end

  def test_evaluate_string_flag
    http = FakeHTTP.new([eval_response('value_type' => 'string', 'value' => 'dark_mode')])
    result = nil
    Net::HTTP.stub(:new, http) { result = Togul::Client.new(make_config).evaluate('ui-theme') }

    assert_equal 'string',    result.value_type
    assert_equal 'dark_mode', result.value
  end

  def test_evaluate_number_flag
    http = FakeHTTP.new([eval_response('value_type' => 'number', 'value' => 55)])
    result = nil
    Net::HTTP.stub(:new, http) { result = Togul::Client.new(make_config).evaluate('threshold') }

    assert_equal 'number', result.value_type
    assert_equal 55,       result.value
  end

  def test_evaluate_json_flag
    json_val = { 'plan' => 'pro', 'limit' => 100 }
    http = FakeHTTP.new([eval_response('value_type' => 'json', 'value' => json_val)])
    result = nil
    Net::HTTP.stub(:new, http) { result = Togul::Client.new(make_config).evaluate('config') }

    assert_equal 'json',  result.value_type
    assert_equal json_val, result.value
  end

  def test_disabled_flag_still_returns_value
    http = FakeHTTP.new([eval_response('enabled' => false, 'value' => 'onur', 'reason' => 'disabled')])
    result = nil
    Net::HTTP.stub(:new, http) { result = Togul::Client.new(make_config).evaluate('test-flag') }

    assert_equal false,    result.enabled
    refute result.enabled?
    assert_equal 'onur',   result.value
    assert_equal 'disabled', result.reason
  end

  # ── Request format ────────────────────────────────────────────────────

  def test_sends_x_api_key_header
    http = FakeHTTP.new([eval_response])
    Net::HTTP.stub(:new, http) { Togul::Client.new(make_config(api_key: 'sdk-key')).evaluate('flag') }

    req = http.requests.first
    assert_equal 'sdk-key', req['X-API-Key']
    assert_nil req['Authorization']
  end

  def test_sends_correct_request_body
    http = FakeHTTP.new([eval_response])
    Net::HTTP.stub(:new, http) do
      Togul::Client.new(make_config).evaluate('my-flag', { 'user_id' => 'u1', 'plan' => 'pro' })
    end

    body = JSON.parse(http.requests.first.body)
    assert_equal 'my-flag', body['flag_key']
    assert_equal 'staging', body['environment_key']
    assert_equal({ 'user_id' => 'u1', 'plan' => 'pro' }, body['context'])
  end

  # ── Cache ─────────────────────────────────────────────────────────────

  def test_cache_hit_on_second_call
    http = FakeHTTP.new([eval_response, eval_response('enabled' => false)])
    client = Togul::Client.new(make_config)
    Net::HTTP.stub(:new, http) do
      client.evaluate('flag', { 'user_id' => 'u1' })
      client.evaluate('flag', { 'user_id' => 'u1' })
    end

    assert_equal 1, http.requests.length
  end

  def test_different_contexts_get_separate_cache_entries
    http = FakeHTTP.new([eval_response('enabled' => true), eval_response('enabled' => false)])
    client = Togul::Client.new(make_config)
    r1, r2 = nil, nil
    Net::HTTP.stub(:new, http) do
      r1 = client.evaluate('flag', { 'user_id' => 'u1' })
      r2 = client.evaluate('flag', { 'user_id' => 'u2' })
    end

    assert_equal true,  r1.enabled
    assert_equal false, r2.enabled
    assert_equal 2, http.requests.length
  end

  def test_different_flags_get_separate_cache_entries
    http = FakeHTTP.new([eval_response, eval_response])
    client = Togul::Client.new(make_config)
    Net::HTTP.stub(:new, http) do
      client.evaluate('flag-a')
      client.evaluate('flag-b')
    end

    assert_equal 2, http.requests.length
  end

  def test_invalidate_cache_forces_refetch
    http = FakeHTTP.new([eval_response('enabled' => true), eval_response('enabled' => false)])
    client = Togul::Client.new(make_config)
    result = nil
    Net::HTTP.stub(:new, http) do
      client.evaluate('flag')
      client.invalidate_cache
      result = client.evaluate('flag')
    end

    assert_equal false, result.enabled
    assert_equal 2, http.requests.length
  end

  def test_invalidate_flag_only_clears_target_flag
    http = FakeHTTP.new([
      eval_response('flag_key' => 'flag-a', 'enabled' => true),
      eval_response('flag_key' => 'flag-b', 'enabled' => true),
      eval_response('flag_key' => 'flag-a', 'enabled' => false),
    ])
    client = Togul::Client.new(make_config)
    a, b = nil, nil
    Net::HTTP.stub(:new, http) do
      client.evaluate('flag-a')
      client.evaluate('flag-b')
      client.invalidate_flag('flag-a')
      a = client.evaluate('flag-a') # miss — refetched
      b = client.evaluate('flag-b') # hit  — from cache
    end

    assert_equal false, a.enabled
    assert_equal true,  b.enabled
    assert_equal 3, http.requests.length
  end

  def test_cache_key_differs_with_different_context_values
    client = Togul::Client.new(make_config)
    k1 = client.send(:build_cache_key, 'flag', { 'user_id' => '1', 'country' => 'TR' })
    k2 = client.send(:build_cache_key, 'flag', { 'user_id' => '1', 'country' => 'US' })
    refute_equal k1, k2
  end

  def test_cache_key_is_deterministic_regardless_of_hash_order
    client = Togul::Client.new(make_config)
    k1 = client.send(:build_cache_key, 'flag', { 'a' => '1', 'b' => '2' })
    k2 = client.send(:build_cache_key, 'flag', { 'b' => '2', 'a' => '1' })
    assert_equal k1, k2
  end

  # ── Retry ─────────────────────────────────────────────────────────────

  def test_retries_on_429_and_succeeds
    http = FakeHTTP.new([FakeResponse.new(429, ''), eval_response])
    client = Togul::Client.new(make_config(retry_count: 2))
    result = nil
    Net::HTTP.stub(:new, http) { result = client.evaluate('flag') }

    assert_equal true, result.enabled
    assert_equal 2, http.requests.length
  end

  def test_retries_on_500_and_succeeds
    http = FakeHTTP.new([FakeResponse.new(500, ''), eval_response])
    client = Togul::Client.new(make_config(retry_count: 2))
    result = nil
    Net::HTTP.stub(:new, http) { result = client.evaluate('flag') }

    assert_equal true, result.enabled
    assert_equal 2, http.requests.length
  end

  def test_does_not_retry_on_4xx_client_errors
    http = FakeHTTP.new([
      error_response(403, 'evaluate.environment_forbidden', 'API key does not have access'),
      eval_response,
    ])
    client = Togul::Client.new(make_config(retry_count: 3))
    Net::HTTP.stub(:new, http) do
      assert_raises(Togul::Error) { client.evaluate('flag') }
    end

    assert_equal 1, http.requests.length
  end

  def test_raises_after_all_retries_exhausted
    http = FakeHTTP.new([FakeResponse.new(500, ''), FakeResponse.new(500, '')])
    client = Togul::Client.new(make_config(retry_count: 2))
    Net::HTTP.stub(:new, http) do
      assert_raises(Togul::Error) { client.evaluate('flag') }
    end
  end

  def test_raises_when_api_key_is_missing
    client = Togul::Client.new(Togul::Config.new(environment: 'staging', api_key: ''))
    assert_raises(Togul::Error) { client.evaluate('flag') }
  end

  # ── Invalidation listeners ────────────────────────────────────────────────

  def test_stream_client_is_loaded_by_the_gem_entry_point
    # Regression: lib/togul.rb did not require stream_client.rb, so
    # start_stream and on_cache_invalidated raised NameError.
    assert defined?(Togul::StreamClient)
  end

  def test_manual_invalidation_notifies_listeners
    client = Togul::Client.new(make_config)
    seen = []
    client.on_cache_invalidated { |flag_key| seen << flag_key }

    client.invalidate_flag('flag-a')
    client.invalidate_cache

    assert_equal ['flag-a', ''], seen
  end

  def test_stream_events_notify_client_listeners
    client = Togul::Client.new(make_config)
    seen = []
    client.on_cache_invalidated { |flag_key| seen << flag_key }

    # Keep the stream thread from opening a real connection.
    original_connect = Togul::StreamClient.instance_method(:connect)
    Togul::StreamClient.define_method(:connect) { nil }
    begin
      client.start_stream
      client.instance_variable_get(:@stream_thread).join
    ensure
      Togul::StreamClient.define_method(:connect, original_connect)
    end
    stream = client.instance_variable_get(:@stream_client)
    stream.send(:handle_event, { 'type' => 'flag.updated', 'flag_key' => 'flag-a' })
    stream.send(:handle_event, { 'type' => 'segment.updated' })

    assert_equal ['flag-a', ''], seen
  end
end
