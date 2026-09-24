# frozen_string_literal: true

require 'json'
require 'time'
require 'open_feature/sdk'
require_relative '../togul'

module Togul
  module OpenFeature
    # OpenFeature provider backed by Togul::Client.
    #
    # Requires the optional "openfeature-sdk" gem and an explicit
    # `require "togul/open_feature"`. Caching, retries and SSE invalidation all
    # stay in Togul::Client; this class only adapts the single evaluate call to
    # OpenFeature's typed resolvers and never raises. Cache invalidations are
    # re-emitted as PROVIDER_CONFIGURATION_CHANGED. Mirrors the PHP provider
    # (togul-php/src/OpenFeature/TogulProvider.php).
    class Provider
      include ::OpenFeature::SDK::Provider::EventEmitter

      Reason = ::OpenFeature::SDK::Provider::Reason
      ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode
      ResolutionDetails = ::OpenFeature::SDK::Provider::ResolutionDetails

      attr_reader :metadata, :client

      # @param client [Togul::Client]
      # @param targeting_key_attribute [String] Context attribute the targeting
      #   key is sent as. Matches the default rule "bucket_by".
      def initialize(client, targeting_key_attribute: 'user_id')
        @client = client
        @targeting_key_attribute = targeting_key_attribute
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: 'Togul').freeze
        @closed = false
        client.on_cache_invalidated { |flag_key| on_invalidated(flag_key) }
      end

      def init(_evaluation_context = nil); end

      # Stop forwarding invalidations. The client is left to its owner.
      def shutdown
        @closed = true
      end

      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, evaluation_context, 'boolean') do |v|
          [v == true || v == false, v]
        end
      end

      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, evaluation_context, 'string') { |v| [v.is_a?(String), v] }
      end

      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, evaluation_context, 'number') { |v| [v.is_a?(Numeric), v] }
      end

      # Togul has a single "number" type; JSON parses "3.0" as a Float.
      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, evaluation_context, 'integer') do |v|
          whole = v.is_a?(Integer) || (v.is_a?(Float) && v.finite? && v == v.floor)
          [whole, whole ? v.to_i : nil]
        end
      end

      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, evaluation_context, 'float') do |v|
          [v.is_a?(Numeric), v.is_a?(Numeric) ? v.to_f : nil]
        end
      end

      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, evaluation_context, 'object') do |v|
          [v.is_a?(Hash) || v.is_a?(Array), v]
        end
      end

      private

      def on_invalidated(flag_key)
        return if @closed

        details = { message: 'Togul cache invalidated' }
        details[:flags_changed] = [flag_key] unless flag_key.to_s.empty?
        emit_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, details)
      end

      # @yieldparam value [Object] the flag value
      # @yieldreturn [Array(Boolean, Object)] [matches, coerced value]
      def resolve(flag_key, default_value, evaluation_context, expected_type)
        begin
          result = @client.evaluate(flag_key, togul_context(evaluation_context))
        rescue Togul::Error => e
          not_found = e.status_code == 404 && e.error_code == 'evaluate.flag_not_found'
          return error(default_value, not_found ? ErrorCode::FLAG_NOT_FOUND : ErrorCode::GENERAL, e.message)
        rescue StandardError => e
          return error(default_value, ErrorCode::GENERAL, e.message)
        end

        # OpenFeature spec: a disabled flag resolves to the caller's default.
        return ResolutionDetails.new(value: default_value, reason: Reason::DISABLED) unless result.enabled?

        # A json flag created without a default stores null: nothing to serve.
        return ResolutionDetails.new(value: default_value, reason: map_reason(result.reason)) if result.value.nil?

        matches, value = yield(result.value)
        unless matches
          return error(default_value, ErrorCode::TYPE_MISMATCH,
                       "Flag \"#{flag_key}\" has value_type \"#{result.value_type}\", requested #{expected_type}")
        end

        ResolutionDetails.new(value: value, reason: map_reason(result.reason))
      end

      def map_reason(reason)
        case reason
        when 'rule_match' then Reason::TARGETING_MATCH
        when 'default' then Reason::DEFAULT
        when 'disabled' then Reason::DISABLED
        else Reason::UNKNOWN
        end
      end

      def error(default_value, code, message)
        ResolutionDetails.new(value: default_value, reason: Reason::ERROR, error_code: code, error_message: message)
      end

      # Togul evaluates against a flat Hash<String, String>, and Togul::Client
      # builds its cache key by concatenating those values.
      def togul_context(evaluation_context)
        return {} if evaluation_context.nil?

        targeting_key_field = ::OpenFeature::SDK::EvaluationContext::TARGETING_KEY
        out = {}
        evaluation_context.fields.each do |key, value|
          next if key == targeting_key_field

          string_value = stringify_attribute(value)
          out[key.to_s] = string_value unless string_value.nil?
        end

        # An explicitly set attribute wins over the targeting key.
        targeting_key = evaluation_context.targeting_key
        if targeting_key && !targeting_key.to_s.empty? && !out.key?(@targeting_key_attribute)
          out[@targeting_key_attribute] = targeting_key.to_s
        end
        out
      end

      # Rules compare with plain string equality ("eq", "in", ...), so every
      # format must match what users type in the dashboard. nil drops the
      # attribute.
      def stringify_attribute(value)
        case value
        when nil then nil
        when true, false then value.to_s
        when Integer then value.to_s
        when Float
          return nil unless value.finite?

          value == value.floor ? value.to_i.to_s : value.to_s
        when Time, DateTime then value.iso8601
        when Hash, Array then JSON.generate(value)
        else value.to_s
        end
      end
    end
  end
end
