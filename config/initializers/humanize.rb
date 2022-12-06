# frozen_string_literal: true

Humanize.configure do |config|
  config.default_locale = :fr  # [:en, :es, :fr, :tr, :de, :id], default: :en
  config.decimals_as = :number # [:digits, :number], default: :digits
end
