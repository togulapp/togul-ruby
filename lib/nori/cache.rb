# frozen_string_literal: true

module Nori
  class Cache
    def initialize(ttl:)
      @ttl = ttl
      @store = {}
      @mutex = Mutex.new
    end

    # @return [Boolean, nil] cached value or nil on miss/expiry
    def get(key)
      @mutex.synchronize do
        entry = @store[key]
        return nil unless entry
        return nil if Time.now.to_f > entry[:expires_at]

        entry[:value]
      end
    end

    def set(key, value)
      @mutex.synchronize do
        @store[key] = {
          value: value,
          expires_at: Time.now.to_f + @ttl
        }
      end
    end

    def flush
      @mutex.synchronize { @store.clear }
    end
  end
end
