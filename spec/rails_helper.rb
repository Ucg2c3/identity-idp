# This file is copied to spec/ when you run 'rails generate rspec:install'

if ENV['COVERAGE']
  require './spec/simplecov_helper'
  SimplecovHelper.start
end

ENV['RAILS_ENV'] = 'test'

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_unit/railtie'
require 'rspec/rails'
require 'spec_helper'
require 'email_spec'
require 'email_spec/rspec'
require 'factory_bot'
require 'view_component/test_helpers'
require 'capybara/rspec'
require 'capybara/webmock'

# Checks for pending migrations before tests are run.
# If you are not using ActiveRecord, you can remove this line.
ActiveRecord::Migration.maintain_test_schema!

# Require all .rb files in spec/support _except_ things that are actually specs.
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each do |f|
  require f unless f.end_with?('_spec.rb')
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!

  config.include ActiveSupport::Testing::TimeHelpers
  config.include AbTestsHelper
  config.include EmailSpec::Helpers
  config.include EmailSpec::Matchers
  config.include AbstractController::Translation
  config.include MailerHelper
  config.include Features::SessionHelper, type: :feature
  config.include Features::StripTagsHelper, type: :feature
  config.include ViewComponent::TestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
  config.include AgreementsHelper
  config.include AnalyticsHelper
  config.include AttemptsApiTrackingHelper
  config.include AwsCloudwatchHelper
  config.include AwsKmsClientHelper
  config.include DiffHelper
  config.include KeyRotationHelper
  config.include OtpHelper
  config.include XmlHelper

  config.before(:suite) do
    Rails.application.load_seed

    class Analytics
      prepend FakeAnalytics::PiiAlerter
      prepend FakeAnalytics::UndocumentedParamsChecker
    end

    begin
      REDIS_POOL.with { |client| client.info }
    rescue RuntimeError => error
      # rubocop:disable Rails/Output
      puts error
      puts 'It appears Redis is not running, but it is required for (some) specs to run'
      exit 1
      # rubocop:enable Rails/Output
    end
  end

  if !ENV['CI'] && !ENV['SKIP_BUILD']
    config.before(js: true) do
      # rubocop:disable Style/GlobalVars
      next if defined?($ran_asset_build)
      $ran_asset_build = true
      # rubocop:enable Style/GlobalVars
      # rubocop:disable Rails/Output
      print '                       Bundling JavaScript and stylesheets... '
      system 'NODE_ENV=production yarn concurrently "yarn:build:*" > /dev/null 2>&1'
      puts '✨ Done!'
      # rubocop:enable Rails/Output

      # The JavaScript assets manifest is cached by the application. Since the preceding build will
      # write a new manifest, instruct the application to refresh the cache from disk.
      Rails.application.config.asset_sources.load_manifest
    end
  end

  config.before(:each) do
    I18n.locale = :en
  end

  config.before(:each, js: true) do
    server = Capybara.current_session.server
    server_domain = "#{server.host}:#{server.port}"
    allow(IdentityConfig.store).to receive(:domain_name).and_return(server_domain)
    default_url_options = ApplicationController.default_url_options.merge(host: server_domain)
    self.default_url_options = default_url_options
    allow(Rails.application.routes).to receive(:default_url_options).and_return(default_url_options)
  end
  config.before(:each, type: :controller) do
    @request.host = IdentityConfig.store.domain_name
  end

  config.before(:each) do
    allow(ValidateEmail).to receive(:mx_valid?).and_return(true)
  end

  config.before(:each) do
    Telephony::Test::Message.clear_messages
    Telephony::Test::Call.clear_calls
    PushNotification::LocalEventQueue.clear!
    REDIS_THROTTLE_POOL.with { |client| client.flushdb } if Identity::Hostdata.config
    REDIS_ATTEMPTS_API_POOL.with { |client| client.flushdb } if Identity::Hostdata.config
  end

  config.before(:each) do
    DocAuth::Mock::DocAuthMockClient.reset!
    descendants = ActiveJob::Base.descendants + [ActiveJob::Base]

    ActiveJob::Base.queue_adapter = :inline
    descendants.each(&:disable_test_adapter)
  end

  config.before(:each) do
    Rails.cache.clear
  end

  config.around(:each, type: :feature) do |example|
    Bullet.enable = true
    Capybara::Webmock.start
    example.run
    Capybara::Webmock.stop
    Bullet.enable = false
  end

  config.around(:each, freeze_time: true) do |example|
    freeze_time { example.run }
  end

  config.after(:each, type: :feature, js: true) do |spec|
    next unless page.driver.browser.respond_to?(:manage)

    # Always get the logs, even if logs are allowed for the spec, since otherwise unexpected
    # messages bleed over between specs.
    javascript_errors = page.driver.browser.logs.get(:browser).map(&:message)
    next if spec.metadata[:allow_browser_log]

    # Temporarily allow for document-capture bundle, since it uses React error boundaries to poll.
    javascript_errors.reject! { |e| e.include? 'submission-complete' }

    # Consider any browser console logging as a failure.
    raise BrowserConsoleLogError.new(javascript_errors) if javascript_errors.present?
  end

  config.around(:each, allow_net_connect_on_start: true) do |example|
    # Avoid "Too many open files - socket(2)" error on some local machines
    WebMock.allow_net_connect!(net_http_connect_on_start: true)
    example.run
    WebMock.disable_net_connect!(
      allow: [
        /localhost/,
        /127\.0\.0\.1/,
        /chromedriver\.storage\.googleapis\.com/, # For fetching a chromedriver binary
      ],
    )
  end

  config.after(:context) do
    reload_ab_tests
  end
end
