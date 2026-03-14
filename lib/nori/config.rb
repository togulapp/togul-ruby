# frozen_string_literal: true

module Nori
  class Config
    attr_reader :base_url, :api_key, :environment, :timeout,
                :cache_ttl, :fallback_mode, :retry_count

    # @param base_url [String] Nori API base URL
    # @param environment [String] Environment key (e.g. "production")
    # @param api_key [String] Environment API key for evaluate/stream requests
    # @param timeout [Numeric] HTTP timeout in seconds
    # @param cache_ttl [Integer] Cache TTL in seconds
    # @param fallback_mode [Symbol] :fail_closed or :fail_open
    # @param retry_count [Integer] Number of retry attempts
    def initialize(
      base_url:,
      environment:,
      api_key: "",
      timeout: 5,
      cache_ttl: 30,
      fallback_mode: :fail_closed,
      retry_count: 2
    )
      @base_url = base_url.chomp("/")
      @api_key = api_key
      @environment = environment
      @timeout = timeout
      @cache_ttl = cache_ttl
      @fallback_mode = fallback_mode
      @retry_count = retry_count
    end
  end
end
