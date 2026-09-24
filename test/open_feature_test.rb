# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/togul/open_feature'

class TogulOpenFeatureProviderTest < Minitest::Test
  Reason = OpenFeature::SDK::Provider::Reason
  ErrorCode = OpenFeature::SDK::Provider::ErrorCode

  def with_responses(*responses)
    http = FakeHTTP.new(responses)
    Net::HTTP.stub(:new, http) { yield Togul::OpenFeature::Provider.new(Togul::Client.new(make_config)), http }
    http
  end

  def sent_context(http)
    JSON.parse(http.requests.last.body)['context']
  end

  def context(targeting_key = nil, **fields)
    OpenFeature::SDK::EvaluationContext.new(targeting_key: targeting_key, **fields)
  end

  def test_resolves_each_type_with_mapped_reasons
    with_responses(
      eval_response,
      eval_response('value_type' => 'string', 'value' => 'dark', 'reason' => 'default'),
      eval_response('value_type' => 'number', 'value' => 42),
      eval_response('value_type' => 'number', 'value' => 2.5),
      eval_response('value_type' => 'json', 'value' => { 'theme' => 'dark' })
    ) do |provider|
      details = provider.fetch_boolean_value(flag_key: 'b', default_value: false)
      assert_equal [true, Reason::TARGETING_MATCH], [details.value, details.reason]

      details = provider.fetch_string_value(flag_key: 's', default_value: 'light')
      assert_equal ['dark', Reason::DEFAULT], [details.value, details.reason]

      assert_equal 42, provider.fetch_integer_value(flag_key: 'i', default_value: 0).value
      assert_equal 2.5, provider.fetch_float_value(flag_key: 'f', default_value: 0.0).value
      assert_equal({ 'theme' => 'dark' }, provider.fetch_object_value(flag_key: 'o', default_value: {}).value)
    end
  end

  def test_unknown_reason_maps_to_unknown
    with_responses(eval_response('reason' => 'something_new')) do |provider|
      assert_equal Reason::UNKNOWN, provider.fetch_boolean_value(flag_key: 'f', default_value: false).reason
    end
  end

  def test_whole_float_is_an_integer_but_a_fraction_is_a_mismatch
    with_responses(
      eval_response('value_type' => 'number', 'value' => 3.0),
      eval_response('value_type' => 'number', 'value' => 1.5)
    ) do |provider|
      assert_equal 3, provider.fetch_integer_value(flag_key: 'whole', default_value: 0).value

      details = provider.fetch_integer_value(flag_key: 'frac', default_value: 7)
      assert_equal [7, ErrorCode::TYPE_MISMATCH], [details.value, details.error_code]
    end
  end

  def test_disabled_and_null_serve_the_default
    with_responses(
      eval_response('enabled' => false, 'value' => true, 'reason' => 'disabled'),
      eval_response('value_type' => 'json', 'value' => nil, 'reason' => 'default')
    ) do |provider|
      details = provider.fetch_boolean_value(flag_key: 'd', default_value: false)
      assert_equal [false, Reason::DISABLED], [details.value, details.reason]

      details = provider.fetch_object_value(flag_key: 'n', default_value: { 'a' => 1 })
      assert_equal [{ 'a' => 1 }, Reason::DEFAULT], [details.value, details.reason]
    end
  end

  def test_errors_resolve_to_the_default
    with_responses(
      eval_response('value_type' => 'string', 'value' => 'dark'),
      error_response(404, 'evaluate.flag_not_found', 'Flag not found'),
      error_response(401, 'unauthorized', 'nope')
    ) do |provider|
      [ErrorCode::TYPE_MISMATCH, ErrorCode::FLAG_NOT_FOUND, ErrorCode::GENERAL].each_with_index do |code, i|
        details = provider.fetch_boolean_value(flag_key: "f#{i}", default_value: true)
        assert_equal [true, Reason::ERROR, code], [details.value, details.reason, details.error_code]
      end
    end
  end

  def test_flattens_the_context
    http = with_responses(eval_response) do |provider|
      provider.fetch_boolean_value(
        flag_key: 'f', default_value: false,
        evaluation_context: context('u1', country: 'TR', beta: true, age: 42, score: 1.5, whole: 2.0,
                                          signup: Time.utc(2026, 1, 2, 3, 4, 5), tags: %w[a b], missing: nil)
      )
    end
    assert_equal(
      { 'user_id' => 'u1', 'country' => 'TR', 'beta' => 'true', 'age' => '42', 'score' => '1.5',
        'whole' => '2', 'signup' => '2026-01-02T03:04:05Z', 'tags' => '["a","b"]' },
      sent_context(http)
    )
  end

  def test_explicit_user_id_wins_and_attribute_is_configurable
    http = with_responses(eval_response) do |provider|
      provider.fetch_boolean_value(flag_key: 'f', default_value: false,
                                   evaluation_context: context('tk', user_id: 'explicit'))
    end
    assert_equal 'explicit', sent_context(http)['user_id']

    http = FakeHTTP.new([eval_response])
    Net::HTTP.stub(:new, http) do
      provider = Togul::OpenFeature::Provider.new(Togul::Client.new(make_config), targeting_key_attribute: 'account_id')
      provider.fetch_boolean_value(flag_key: 'f', default_value: false, evaluation_context: context('acc-1'))
    end
    assert_equal({ 'account_id' => 'acc-1' }, sent_context(http))
  end

  def test_forwards_invalidations_until_shutdown
    client = Togul::Client.new(make_config)
    provider = Togul::OpenFeature::Provider.new(client)
    events = []
    config = Object.new
    config.define_singleton_method(:dispatch_provider_event) { |_p, type, details| events << [type, details] }
    provider.send(:attach, config)

    client.invalidate_flag('banner')
    client.invalidate_cache
    changed = OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED
    assert_equal [changed, changed], events.map(&:first)
    assert_equal ['banner'], events[0][1][:flags_changed]
    refute events[1][1].key?(:flags_changed)

    provider.shutdown
    client.invalidate_cache
    assert_equal 2, events.size
  end

  def test_end_to_end_through_the_openfeature_api
    http = FakeHTTP.new([eval_response('value_type' => 'string', 'value' => 'dark')])
    value = nil
    Net::HTTP.stub(:new, http) do
      OpenFeature::SDK.configure do |config|
        config.set_provider_and_wait(Togul::OpenFeature::Provider.new(Togul::Client.new(make_config)))
      end
      value = OpenFeature::SDK.build_client.fetch_string_value(
        flag_key: 'theme', default_value: 'light', evaluation_context: context('u1')
      )
    end
    assert_equal 'dark', value
    assert_equal 'u1', sent_context(http)['user_id']
  end
end
