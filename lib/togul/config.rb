# frozen_string_literal: true

module Togul
  class Config
    DEFAULT_BASE_URL = 'https://api.togul.io'

    attr_reader :api_key, :environment, :timeout, :cache_ttl, :fallback_mode, :retry_count, :base_url

    # @param environment [String] Environment key (e.g. "production")
    # @param api_key [String] Environment API key for evaluate/stream requests
    # @param timeout [Numeric] HTTP timeout in seconds
    # @param cache_ttl [Integer] Cache TTL in seconds
    # @param fallback_mode [Symbol] :fail_closed or :fail_open
    # @param retry_count [Integer] Number of retry attempts
    # @param base_url [String, nil] Override default base URL (optional)
    def initialize(
      environment:,
      api_key: '',
      timeout: 5,
      cache_ttl: 30,
      fallback_mode: :fail_closed,
      retry_count: 2,
      base_url: nil
    )
      @base_url = base_url&.chomp('/') || DEFAULT_BASE_URL
      @api_key = api_key
      @environment = environment
      @timeout = timeout
      @cache_ttl = cache_ttl
      @fallback_mode = fallback_mode
      @retry_count = retry_count
    end
  end
end
