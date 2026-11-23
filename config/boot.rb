ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# Windows libpq otherwise tries GSS and Postgres closes the socket.
ENV["PGGSSENCMODE"] ||= "disable" if Gem.win_platform?

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
