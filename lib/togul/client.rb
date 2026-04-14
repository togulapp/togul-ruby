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
    end

    # Evaluate a feature flag.
    #
    # @param key [String] Flag key
    # @param context [Hash<String, String>] User/request context
    # @return [Boolean] Whether the flag is enabled
    def enabled?(key, context = {})
      cache_key = build_cache_key(key, context)

      cached = @cache.get(cache_key)
      return cached unless cached.nil?

      value = evaluate(key, context)
      @cache.set(cache_key, value)
      value
    rescue StandardError
      case @config.fallback_mode
      when :fail_open then true
      else false
      end
    end

    # Clear all cached flag values.
    def invalidate_cache
      @cache.flush
    end

    # Clear a specific flag from cache.
    def invalidate_flag(key)
      @cache.invalidate_flag(key)
    end

    # Start SSE stream for real-time cache invalidation.
    def stream
      @stream_client ||= StreamClient.new(@config, @cache)
    end

    # Register a listener for cache invalidation events.
    def on_cache_invalidated(&block)
      stream.on_cache_invalidated(&block)
    end

    private

    def evaluate(key, context)
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
          return body['value'] == true
        rescue Error
          raise
        rescue StandardError => e
          last_error = e
        end
      end

      raise Error.new("all retries failed: #{last_error}")
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
