module Officer
  class DashboardsController < BaseController
    def show
      @next_event = Event.upcoming.first
      @recent_events = Event.chronological.last(8).reverse
      @member_count = User.count
    end
  end
end
