require "rails_helper"
require "erb"
require "yaml"

RSpec.describe "Database configuration" do
     def test_database(**values)
          keys = %w[DATABASE_URL TEST_DATABASE_URL TEST_DATABASE_NAME]
          saved = keys.to_h { |key| [ key, ENV[key] ] }
          keys.each { |key| ENV.delete(key) }
          values.each { |key, value| ENV[key.to_s] = value }
          config = YAML.safe_load(ERB.new(Rails.root.join("config/database.yml").read).result, aliases: true)
          ActiveRecord::DatabaseConfigurations.new(config).configs_for(env_name: "test", name: "primary").configuration_hash
        ensure
             saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
     end

     it "does not let a development DATABASE_URL silently select the test database" do
          config = test_database(DATABASE_URL: "postgresql://review@development.example.test/live_data")
          expect(config[:database]).to eq("pt_society_test")
          expect(config[:host]).not_to eq("development.example.test")
     end

     it "supports an explicitly configured hosted test database" do
          config = test_database(TEST_DATABASE_URL: "postgresql://review@tests.example.test/specs?sslmode=require")
          expect(config).to include(host: "tests.example.test", database: "specs", sslmode: "require")
     end

     it "supports a configured test database name with the normal host settings" do
          expect(test_database(TEST_DATABASE_NAME: "custom_specs")[:database]).to eq("custom_specs")
     end
end
