class RsvpsController < ApplicationController
  before_action :require_authentication
  before_action :set_event

  def create
    if @event.upcoming?
      @event.rsvps.find_or_create_by!(user: current_user)
      redirect_to event_path(@event), notice: "You're going."
    else
      redirect_to event_path(@event), alert: "That event already happened."
    end
  end

  def destroy
    @event.rsvps.find_by(user: current_user)&.destroy
    redirect_to event_path(@event), notice: "You're no longer listed as going."
  end

  private

  def set_event
    @event = Event.find(params[:event_id])
  end
end
