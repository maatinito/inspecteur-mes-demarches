# frozen_string_literal: true

module Baserow
  class APIError < StandardError
    attr_reader :error_data, :status_code

    def initialize(error_data, status_code)
      @error_data = error_data
      @status_code = status_code

      message = if error_data.is_a?(Hash)
                  error_data['error'] || error_data['detail'] || error_data.inspect
                else
                  error_data.to_s
                end

      super(message)
    end
  end
end
