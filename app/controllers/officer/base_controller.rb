module Officer
  class BaseController < ApplicationController
    before_action :require_authentication
    before_action :require_officer
  end
end
