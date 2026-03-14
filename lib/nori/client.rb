# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Nori
  class Client
    # @param config [Nori::Config]
    def initialize(config)
      @config = config
      @cache = Cache.new(ttl: config.cache_ttl)
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
    rescue StandardError => e
      case @config.fallback_mode
      when :fail_open then true
      else false
      end
    end

    # Clear all cached flag values.
    def invalidate_cache
      @cache.flush
    end

    private

    def evaluate(key, context)
      last_error = nil

      @config.retry_count.times do |attempt|
        sleep(attempt * 0.1) if attempt > 0

        begin
          uri = URI("#{@config.base_url}/api/v1/evaluate")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @config.timeout
          http.read_timeout = @config.timeout

          request = Net::HTTP::Post.new(uri.path)
          request["Content-Type"] = "application/json"
          request["Authorization"] = "Bearer #{@config.api_key}" unless @config.api_key.empty?

          request.body = JSON.generate({
            flag_key: key,
            environment_key: @config.environment,
            context: context
          })

          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            last_error = "unexpected status #{response.code}"
            next
          end

          body = JSON.parse(response.body)
          return body["value"] == true
        rescue StandardError => e
          last_error = e
        end
      end

      raise "nori-sdk: all retries failed: #{last_error}"
    end

    def build_cache_key(key, context)
      cache_key = "#{key}:#{@config.environment}"
      cache_key += ":#{context['user_id']}" if context.key?("user_id")
      cache_key
    end
  end
end
