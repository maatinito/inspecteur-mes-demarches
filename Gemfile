# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.4'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 7.2.0'
# Use postgresql as the database for Active Record
gem 'pg', '>= 0.18', '< 2.0'
# Use Puma as the app server
gem 'puma', '>= 3.12.6'
# Use SCSS for stylesheets
gem 'cssbundling-rails'
gem 'json', '>= 2.10.0'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'
# See https://github.com/rails/execjs#readme for more supported runtimes
# gem 'mini_racer', platforms: :ruby

# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails', '~> 5.0'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.5'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use ActiveStorage variant
# gem 'mini_magick', '~> 4.8'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Reduces boot times through caching; required in config/boot.rb
gem 'aws-sdk-s3', '>= 1.208.0'
gem 'bootsnap', require: false
gem 'caxlsx'
gem 'combine_pdf'
gem 'csv'
gem 'delayed_cron_job' # Cron jobs
gem 'delayed_job_active_record'
gem 'delayed_job_web'
gem 'devise', '~> 4.7'
gem 'devise-i18n'
gem 'docx', '~> 0.8.0'
gem 'fugit'
gem 'graphql-client'
gem 'haml-rails'
gem 'humanize'
gem 'iban-tools'
gem 'jquery-rails'
gem 'kramdown'
gem 'kramdown-parser-gfm' # GitHub Flavored Markdown
gem 'mailjet'
gem 'mime-types'
gem 'net-imap', '>= 0.5.7', require: false
gem 'net-pop', require: false
gem 'net-smtp', require: false
gem 'phonelib'
gem 'roo-xls'
gem 'rubyXL'
gem 'sablon'
gem 'sentry-delayed_job'
gem 'sentry-rails'
gem 'sentry-ruby'
gem 'sinatra', '>= 4.2.0'
gem 'sprockets-rails'
gem 'typhoeus'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby] # Windows does not include zoneinfo files, so bundle the tzinfo-data gem

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'pdf-reader'
  gem 'rspec'
  gem 'rspec_junit_formatter'
  gem 'rspec-rails'
  gem 'spring', '~> 4.0'
  gem 'spring-commands-rspec'
  gem 'spring-watcher-listen', '~> 2.0'
  gem 'timecop'
  gem 'vcr'
  gem 'webmock'
end

group :development do
  gem 'annotate'
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'listen', '~> 3.7'
  gem 'web-console', '>= 3.3.0'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'bundler-audit', require: false
  gem 'haml-lint'
  gem 'letter_opener_web'
  gem 'mry'
  gem 'rubocop', require: false
  gem 'rubocop-rails_config'
  gem 'rubocop-rspec', require: false
  gem 'scss_lint', require: false
end
