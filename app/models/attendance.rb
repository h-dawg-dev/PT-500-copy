class Attendance < ApplicationRecord
  include PointBalanceProtection

  belongs_to :user
  belongs_to :event
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :user_id, uniqueness: { scope: :event_id }
  before_destroy :preserve_member_points

  # What this check-in is worth to the person who attended. Officers are recorded but earn nothing.
  def points_awarded
    user.earns_points? ? event.points : 0
  end

  private

  def preserve_member_points
    # Event deletion checks all attendees before cascading. User deletion removes the entire ledger.
    return if destroyed_by_association

    recorded_event = Event.lock.find(event_id)
    return if preserve_point_balances(recorded_event, points: recorded_event.points, user_ids: user_id)

    throw :abort
  end
end
