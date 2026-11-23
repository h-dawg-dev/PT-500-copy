class EventsController < ApplicationController
  before_action :require_authentication

  def index
    @query = params[:q].to_s.strip
    @filter = params[:filter].to_s.presence_in(%w[upcoming past all]) || (@query.present? ? "all" : "upcoming")
    @events = case @filter
    when "past" then Event.past
    when "all" then Event.order(starts_at: :desc)
    else Event.upcoming
    end
    @events = @events.search(@query, include_attendees: current_user.officer?).preload(:term, :rsvps)
    @events = @events.preload(:attendees) if current_user.officer?
  end

  def show
    @event = Event.find(params[:id])
    @attended = @event.attended_by?(current_user)
    @rsvped = @event.rsvped_by?(current_user)
  end
end
