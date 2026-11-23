class HelpController < ApplicationController
     before_action :require_authentication

  def show
       @guides = HelpGuide.for(current_user)
  end
end
