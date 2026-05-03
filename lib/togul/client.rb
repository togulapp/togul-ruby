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
      evaluate_result(key, context).enabled?
    rescue StandardError
      case @config.fallback_mode
      when :fail_open then true
      else false
      end
    end

    # Evaluate a feature flag and return the full result with typed value accessors.
    #
    # @param key [String] Flag key
    # @param context [Hash<String, String>] User/request context
    # @return [Togul::EvaluateResult]
    def evaluate_result(key, context = {})
      cache_key = build_cache_key(key, context)

      cached = @cache.get(cache_key)
      return cached unless cached.nil?

      result = evaluate(key, context)
      @cache.set(cache_key, result)
      result
    end

    # Evaluate a boolean flag.
    #
    # @param key [String] Flag key
    # @param context [Hash<String, String>] User/request context
    # @param fallback [Boolean] Value to return on error or type mismatch
    # @return [Boolean]
    def evaluate_bool(key, context = {}, fallback: false)
      evaluate_result(key, context).bool_value(fallback)
    rescue StandardError
      fallback
    end

    # Evaluate a string flag.
    #
    # @param key [String] Flag key
    # @param context [Hash<String, String>] User/request context
    # @param fallback [String] Value to return on error or type mismatch
    # @return [String]
    def evaluate_string(key, context = {}, fallback: '')
      evaluate_result(key, context).string_value(fallback)
    rescue StandardError
      fallback
    end

    # Evaluate a number flag.
    #
    # @param key [String] Flag key
    # @param context [Hash<String, String>] User/request context
    # @param fallback [Float] Value to return on error or type mismatch
    # @return [Float]
    def evaluate_number(key, context = {}, fallback: 0.0)
      evaluate_result(key, context).number_value(fallback)
    rescue StandardError
      fallback
    end

    # Evaluate a JSON flag.
    #
    # @param key [String] Flag key
    # @param context [Hash<String, String>] User/request context
    # @param fallback [Object] Value to return on error or type mismatch
    # @return [Object]
    def evaluate_json(key, context = {}, fallback: nil)
      evaluate_result(key, context).json_value(fallback)
    rescue StandardError
      fallback
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
          return EvaluateResult.new(
            flag_key:   body['flag_key'] || key,
            enabled:    body['enabled'] == true,
            value_type: body['value_type'].to_s,
            raw_value:  body['value'],
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
