# frozen_string_literal: true

if ENV["CLERK_SECRET_KEY"].to_s.start_with?("sk_") && ENV["CLERK_PUBLISHABLE_KEY"].to_s.start_with?("pk_")
  Clerk.configure do |config|
    config.excluded_routes = [ "/up" ]
  end
else
  Rails.application.config.middleware.delete(Clerk::Rack::Middleware)
end
