class HomeController < ApplicationController
  def show
    return unless signed_in?

    @next_event = Event.upcoming.first
    @term = Term.current
    @points_earned = current_user.points_earned(@term || :current)
    @required_points = current_user.required_points_for(@term || :current)
    @missing_category_points = current_user.missing_category_points(@term || :current)
    @points_requirement_met = current_user.points_requirement_met?(@term || :current)
    @history = current_user.points_history(@term, limit: 8)
  end
end
