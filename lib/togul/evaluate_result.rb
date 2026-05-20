# frozen_string_literal: true

module Togul
  class EvaluateResult
    attr_reader :flag_key, :enabled, :value_type, :value, :reason

    def initialize(flag_key:, enabled:, value_type:, value:, reason:)
      @flag_key   = flag_key
      @enabled    = enabled
      @value_type = value_type
      @value      = value
      @reason     = reason
    end

    def enabled?
      @enabled == true
    end
  end
end
