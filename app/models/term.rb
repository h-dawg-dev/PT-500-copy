class Term < ApplicationRecord
  has_many :events, dependent: :nullify
  has_many :point_adjustments, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :starts_on, presence: true
  validates :ends_on, presence: true
  validates :required_points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :required_professional_points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :required_social_points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ends_on_or_after_start
  validate :dates_do_not_overlap
  after_save :reassign_events!, if: -> { saved_change_to_starts_on? || saved_change_to_ends_on? }

  scope :chronological, -> { order(:starts_on) }
  scope :covering, ->(time) {
    date = time.in_time_zone.to_date
    where("starts_on <= :date AND ends_on >= :date", date: date)
  }

  def self.current(at = Time.current)
    covering(at).order(starts_on: :desc).first
  end

  def covers?(time)
    return false if time.blank?

    date = time.in_time_zone.to_date
    starts_on <= date && ends_on >= date
  end

  def required_category_points
    {
      "professional" => required_professional_points,
      "social" => required_social_points
    }
  end

  # Date maintenance and event reassignment share a transaction, including attendance totals.
  # Also callable for repairing events created before term setup was available.
  def reassign_events!
    transaction do
      range = starts_on.in_time_zone...ends_on.next_day.in_time_zone
      Event.where(term_id: id).or(Event.where(starts_at: range)).find_each do |event|
        expected = Term.current(event.starts_at)
        next if event.term_id == expected&.id

        event.update!(term: expected)
      end
    end
  end

  private

  def ends_on_or_after_start
    return if ends_on.blank? || starts_on.blank?
    return if ends_on >= starts_on

    errors.add(:ends_on, "must be on or after the start")
  end

  def dates_do_not_overlap
    return if starts_on.blank? || ends_on.blank? || ends_on < starts_on
    return unless self.class.where.not(id: id).where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on).exists?

    errors.add(:base, "Term dates must not overlap another term.")
  end
end
