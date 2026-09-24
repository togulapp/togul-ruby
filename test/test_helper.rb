# frozen_string_literal: true

require 'minitest/mock'
require 'minitest/autorun'
require 'json'
require 'net/http'
require_relative '../lib/togul'

# Minimal HTTP stubs — no external test framework needed.
class FakeHTTP
  attr_reader :requests

  def initialize(responses)
    @responses = responses.dup
    @requests  = []
  end

  attr_accessor :use_ssl, :open_timeout, :read_timeout

  def request(req)
    @requests << req
    @responses.shift || raise('FakeHTTP: no more responses')
  end
end

class FakeResponse
  attr_reader :code, :body

  def initialize(status, body, success: nil)
    @code    = status.to_s
    @body    = body
    @success = success.nil? ? (status < 400) : success
  end

  def is_a?(klass)
    return @success if klass == Net::HTTPSuccess
    super
  end
end

def make_config(overrides = {})
  Togul::Config.new(
    environment: overrides.fetch(:environment, 'staging'),
    api_key:     overrides.fetch(:api_key, 'test-key'),
    retry_count: overrides.fetch(:retry_count, 1),
    base_url:    'http://localhost:8080'
  )
end

def eval_response(overrides = {})
  body = {
    'flag_key'   => 'test-flag',
    'enabled'    => true,
    'value_type' => 'boolean',
    'value'      => true,
    'reason'     => 'rule_match'
  }.merge(overrides)
  FakeResponse.new(200, JSON.generate(body))
end

def error_response(status, code, message)
  FakeResponse.new(status, JSON.generate({ 'code' => code, 'message' => message }))
end
