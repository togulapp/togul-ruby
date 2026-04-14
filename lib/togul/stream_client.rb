# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Togul
  class StreamClient
    def initialize(config, cache)
      @config = config
      @cache = cache
      @listeners = []
    end

    def connect
      backoff = 1

      loop do
        stream_once
      rescue Error => e
        raise if [401, 403].include?(e.status_code)

        sleep(backoff)
        backoff = [backoff * 2, 30].min
      end
    end

    def on_cache_invalidated(&block)
      @listeners << block
    end

    private

    def stream_once
      raise Error.new('API key is required') if @config.api_key.empty?

      uri = URI("#{@config.base_url}/api/v1/stream")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Get.new(uri.path)
      request['Accept'] = 'text/event-stream'
      request['X-API-Key'] = @config.api_key

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error.new("stream failed: #{response.code}", status_code: response.code.to_i)
      end

      response.read_body do |chunk|
        parse_sse(chunk)
      end
    end

    def parse_sse(buffer)
      buffer.each_line do |line|
        next unless line.start_with?('data: ')

        data = line[6..].strip
        event = JSON.parse(data)
        handle_event(event)
      end
    end

    def handle_event(event)
      flag_key = event['flag_key'] || ''

      if flag_key != ''
        @cache.invalidate_flag(flag_key)
        notify_listeners(flag_key)
      else
        @cache.flush
        notify_listeners('')
      end
    end

    def notify_listeners(flag_key)
      @listeners.each { |listener| listener.call(flag_key) }
    end
  end
end
