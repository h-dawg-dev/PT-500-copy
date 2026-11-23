# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
ENV["CLERK_SKIP_RAILTIE"] ||= "true"
ENV["CLERK_SECRET_KEY"] ||= "sk_test_dummy"
ENV["CLERK_PUBLISHABLE_KEY"] ||= "pk_test_dummy"
ENV["CLERK_SIGN_IN_URL"] ||= "https://example.com/sign-in"

require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include AuthHelpers, type: :request
  config.include TestUsers
end
