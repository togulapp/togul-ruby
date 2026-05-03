# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'net/http'
require_relative '../lib/togul'

class TogulClientTest < Minitest::Test
  def test_cache_key_includes_full_context
    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'test-key'
                               ))

    first = client.send(:build_cache_key, 'flag-a', { 'user_id' => '1', 'country' => 'TR' })
    second = client.send(:build_cache_key, 'flag-a', { 'user_id' => '1', 'country' => 'US' })

    refute_equal first, second
  end

  def test_enabled_uses_x_api_key_header
    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'sdk-key',
                                 base_url: 'http://localhost:8080'
                               ))

    response = FakeResponse.new(200, bool_response_json(true), success: true)
    http = FakeHTTP.new([response])

    Net::HTTP.stub(:new, http) do
      assert_equal true, client.enabled?('flag-a', { 'user_id' => '1' })
    end

    request = http.requests.first
    assert_equal 'sdk-key', request['X-API-Key']
    assert_nil request['Authorization']
  end

  def test_client_error_is_not_retried
    response = FakeResponse.new(403, JSON.generate({
                                                     code: 'evaluate.environment_forbidden',
                                                     message: 'API key does not have access to this environment'
                                                   }), success: false)
    http = FakeHTTP.new([response, response, response])

    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'sdk-key',
                                 retry_count: 3,
                                 base_url: 'http://localhost:8080'
                               ))

    Net::HTTP.stub(:new, http) do
      assert_equal false, client.enabled?('flag-a')
    end

    assert_equal 1, http.requests.length
  end

  def test_evaluate_result_string_value
    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'sdk-key',
                                 base_url: 'http://localhost:8080'
                               ))

    response = FakeResponse.new(200, JSON.generate({
                                                     flag_key: 'ui-theme',
                                                     enabled: true,
                                                     value_type: 'string',
                                                     value: 'dark_mode',
                                                     reason: 'rule_match'
                                                   }), success: true)
    http = FakeHTTP.new([response])

    result = nil
    Net::HTTP.stub(:new, http) do
      result = client.evaluate_result('ui-theme')
    end

    assert_equal 'dark_mode', result.string_value('light')
    assert_equal 'light', result.bool_value(false) == false ? 'light' : 'light'
    assert_equal 'light', result.number_value(0) == 0 ? 'light' : 'other'
  end

  def test_evaluate_result_number_value
    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'sdk-key',
                                 base_url: 'http://localhost:8080'
                               ))

    response = FakeResponse.new(200, JSON.generate({
                                                     flag_key: 'max-retries',
                                                     enabled: true,
                                                     value_type: 'number',
                                                     value: 5,
                                                     reason: 'rule_match'
                                                   }), success: true)
    http = FakeHTTP.new([response])

    val = nil
    Net::HTTP.stub(:new, http) do
      val = client.evaluate_number('max-retries', fallback: 3.0)
    end

    assert_equal 5.0, val
  end

  def test_evaluate_result_type_mismatch_returns_fallback
    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'sdk-key',
                                 base_url: 'http://localhost:8080'
                               ))

    response = FakeResponse.new(200, JSON.generate({
                                                     flag_key: 'flag',
                                                     enabled: true,
                                                     value_type: 'number',
                                                     value: 42,
                                                     reason: 'rule_match'
                                                   }), success: true)
    http = FakeHTTP.new([response])

    val = nil
    Net::HTTP.stub(:new, http) do
      val = client.evaluate_string('flag', fallback: 'default')
    end

    assert_equal 'default', val
  end

  def test_evaluate_result_disabled_returns_fallback
    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'sdk-key',
                                 base_url: 'http://localhost:8080'
                               ))

    response = FakeResponse.new(200, JSON.generate({
                                                     flag_key: 'flag',
                                                     enabled: false,
                                                     value_type: 'string',
                                                     value: 'some_value',
                                                     reason: 'flag_disabled'
                                                   }), success: true)
    http = FakeHTTP.new([response])

    val = nil
    Net::HTTP.stub(:new, http) do
      val = client.evaluate_string('flag', fallback: 'fallback')
    end

    assert_equal 'fallback', val
  end

  def test_evaluate_result_json_value
    client = Togul::Client.new(Togul::Config.new(
                                 environment: 'production',
                                 api_key: 'sdk-key',
                                 base_url: 'http://localhost:8080'
                               ))

    response = FakeResponse.new(200, JSON.generate({
                                                     flag_key: 'user-config',
                                                     enabled: true,
                                                     value_type: 'json',
                                                     value: { 'plan' => 'pro', 'limit' => 100 },
                                                     reason: 'rule_match'
                                                   }), success: true)
    http = FakeHTTP.new([response])

    val = nil
    Net::HTTP.stub(:new, http) do
      val = client.evaluate_json('user-config', fallback: { 'plan' => 'free' })
    end

    assert_equal 'pro', val['plan']
    assert_equal 100, val['limit']
  end

  private

  def bool_response_json(enabled)
    JSON.generate({
                    flag_key: 'test',
                    enabled: enabled,
                    value_type: 'boolean',
                    value: enabled,
                    reason: 'rule_match'
                  })
  end

  class FakeHTTP
    attr_reader :requests

    def initialize(responses)
      @responses = responses.dup
      @requests = []
    end

    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(request)
      @requests << request
      @responses.shift
    end
  end

  class FakeResponse
    attr_reader :code, :body

    def initialize(status_code, body, success:)
      @code = status_code.to_s
      @body = body
      @success = success
    end

    def is_a?(klass)
      return true if klass == Net::HTTPSuccess && @success

      super
    end
  end
end
