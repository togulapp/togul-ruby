# frozen_string_literal: true

module Nori
  class Error < StandardError
    attr_reader :status_code, :error_code

    def initialize(message = nil, status_code: nil, error_code: nil)
      super(message)
      @status_code = status_code
      @error_code = error_code
    end
  end
end
