class Rsvp < ApplicationRecord
  belongs_to :user
  belongs_to :event

  validates :user_id, uniqueness: { scope: :event_id }
  validate :event_is_upcoming, on: :create

  private

  def event_is_upcoming
    return if event.blank? || event.upcoming?

    errors.add(:event, "has already happened")
  end
end
