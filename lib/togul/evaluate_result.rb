# frozen_string_literal: true

module Togul
  class EvaluateResult
    attr_reader :flag_key, :enabled, :value_type, :reason

    def initialize(flag_key:, enabled:, value_type:, raw_value:, reason:)
      @flag_key   = flag_key
      @enabled    = enabled
      @value_type = value_type
      @raw_value  = raw_value
      @reason     = reason
    end

    def enabled?
      @enabled == true
    end

    def bool_value(fallback = false)
      return fallback unless enabled? && @value_type == 'boolean'
      return fallback unless @raw_value == true || @raw_value == false

      @raw_value
    end

    def string_value(fallback = '')
      return fallback unless enabled? && @value_type == 'string'
      return fallback unless @raw_value.is_a?(String)

      @raw_value
    end

    def number_value(fallback = 0.0)
      return fallback unless enabled? && @value_type == 'number'
      return fallback unless @raw_value.is_a?(Numeric)

      @raw_value.to_f
    end

    def json_value(fallback = nil)
      return fallback unless enabled? && @value_type == 'json'

      @raw_value.nil? ? fallback : @raw_value
    end
  end
end
