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

    response = FakeResponse.new(200, JSON.generate({ value: true }), success: true)
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
