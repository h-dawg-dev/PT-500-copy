module Officer
  class EventsController < BaseController
    before_action :set_event, only: %i[ show edit update destroy ]

    def index
      @query = params[:q].to_s.strip
      @events = Event.search(@query, include_attendees: true).preload(:attendances, :attendees, :term, :rsvps).order(starts_at: :desc)
    end

    def show
      @members = User.order(:last_name, :first_name, :email)
      @attendance_by_user_id = @event.attendances.includes(:user).index_by(&:user_id)
      @rsvp_by_user_id = @event.rsvps.index_by(&:user_id)
    end

    def new
      @event = Event.new(starts_at: default_start, ends_at: default_start + 1.hour, points: 1)
    end

    def create
      @event = Event.new(event_params)
      @event.created_by = current_user

      if @event.save
        redirect_to officer_event_path(@event), notice: "Event is on the board."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @event.update(event_params)
        redirect_to officer_event_path(@event), notice: "Event updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @event.destroy
        redirect_to officer_events_path, notice: "Event taken off the board."
      else
        redirect_to officer_event_path(@event), alert: @event.errors.full_messages.to_sentence, status: :see_other
      end
    end

    private

    def set_event
      @event = Event.find(params[:id])
    end

    def event_params
      params.require(:event).permit(:title, :location, :starts_at, :ends_at, :points, :category, :notes)
    end

    def default_start
      Time.zone.now.change(min: 0, sec: 0) + 1.hour
    end
  end
end
