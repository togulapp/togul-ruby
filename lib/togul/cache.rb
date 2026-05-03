# frozen_string_literal: true

module Togul
  class Cache
    def initialize(ttl:)
      @ttl = ttl
      @store = {}
      @mutex = Mutex.new
    end

    # @return [EvaluateResult, nil] cached result or nil on miss/expiry/stale
    def get(key)
      @mutex.synchronize do
        entry = @store[key]
        return nil unless entry
        return nil if Time.now.to_f > entry[:expires_at]

        result = entry[:value]
        # Treat entries with blank value_type as stale (legacy/invalid format).
        return nil if result.value_type.to_s.empty?

        result
      end
    end

    def set(key, result)
      @mutex.synchronize do
        @store[key] = {
          value:      result,
          expires_at: Time.now.to_f + @ttl
        }
      end
    end

    def flush
      @mutex.synchronize { @store.clear }
    end

    def invalidate_flag(flag_key)
      prefix = "#{flag_key}:"
      @mutex.synchronize do
        @store.delete_if { |key, _| key.start_with?(prefix) }
      end
    end
  end
end
