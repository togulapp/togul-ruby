# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Togul
  class Client
    # @param config [Togul::Config]
    def initialize(config)
      @config = config
      @cache = Cache.new(ttl: config.cache_ttl)
      @stream_client = nil
      @listeners = []
    end

    # Evaluate a feature flag and return the result mirroring the API response.
    #
    # @param key [String] Flag key
    # @param context [Hash<String, String>] User/request context
    # @return [Togul::EvaluateResult]
    def evaluate(key, context = {})
      cache_key = build_cache_key(key, context)

      cached = @cache.get(cache_key)
      return cached unless cached.nil?

      result = fetch_evaluation(key, context)
      @cache.set(cache_key, result)
      result
    end

    # Clear all cached flag values.
    def invalidate_cache
      @cache.flush
      notify_listeners('')
    end

    # Clear a specific flag from cache.
    def invalidate_flag(key)
      @cache.invalidate_flag(key)
      notify_listeners(key)
    end

    # Start the SSE stream in a background thread for real-time cache invalidation.
    # Subsequent calls are no-ops; the thread runs until the process exits.
    def start_stream
      unless @stream_client
        @stream_client = StreamClient.new(@config, @cache)
        # The stream invalidates the cache itself; forward so listeners fire
        # for stream events exactly as for manual invalidation.
        @stream_client.on_cache_invalidated { |flag_key| notify_listeners(flag_key) }
      end
      @stream_thread ||= Thread.new { @stream_client.connect }
      nil
    end

    # Register a listener for cache invalidation, called with the flag key (or
    # "" when the whole cache was cleared) for both manual invalidation and
    # stream events. Call start_stream separately to receive stream events.
    def on_cache_invalidated(&block)
      @listeners << block
      nil
    end

    private

    def fetch_evaluation(key, context)
      raise Error.new('API key is required') if @config.api_key.empty?

      last_error = nil

      @config.retry_count.times do |attempt|
        sleep(attempt * 0.1) if attempt > 0

        begin
          uri = URI("#{@config.base_url}/api/v1/evaluate")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = @config.timeout
          http.read_timeout = @config.timeout

          request = Net::HTTP::Post.new(uri.path)
          request['Content-Type'] = 'application/json'
          request['X-API-Key'] = @config.api_key

          request.body = JSON.generate({
                                         flag_key: key,
                                         environment_key: @config.environment,
                                         context: context
                                       })

          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            last_error = build_api_error(response)
            raise last_error unless should_retry?(response.code.to_i)

            next
          end

          body = JSON.parse(response.body)
          return EvaluateResult.new(
            flag_key:   body['flag_key'] || key,
            enabled:    body['enabled'] == true,
            value_type: body['value_type'].to_s,
            value:      body['value'],
            reason:     body['reason'].to_s
          )
        rescue Error
          raise
        rescue StandardError => e
          last_error = e
        end
      end

      raise Error.new("all retries failed: #{last_error}")
    end

    def notify_listeners(flag_key)
      @listeners.each { |listener| listener.call(flag_key) }
    end

    def build_cache_key(key, context)
      serialized_context = context.sort.map { |context_key, value| "#{context_key}=#{value}" }
      ([key, @config.environment] + serialized_context).join(':')
    end

    def should_retry?(status_code)
      status_code == 429 || status_code >= 500
    end

    def build_api_error(response)
      body = {}
      body = JSON.parse(response.body) unless response.body.to_s.empty?

      Error.new(
        body['message'] || "unexpected status #{response.code}",
        status_code: response.code.to_i,
        error_code: body['code']
      )
    end
  end
end
