class Event < ApplicationRecord
  include PointBalanceProtection

  MAX_POINTS = 2_147_483_647
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :term, optional: true
  has_many :attendances, dependent: :destroy
  has_many :attendees, through: :attendances, source: :user
  has_many :rsvps, dependent: :destroy
  has_many :rsvp_users, through: :rsvps, source: :user

  enum :category, { general: 0, professional: 1, social: 2 }, default: :general, validate: true

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_POINTS }
  validates :getinvolved_reference, uniqueness: true, allow_nil: true
  validate :ends_after_start
  validate :preserve_points_on_update, on: :update
  before_validation :assign_term_from_starts_at
  before_destroy :preserve_points_on_destroy, prepend: true

  scope :chronological, -> { order(:starts_at) }
  scope :upcoming, -> { where("starts_at >= ?", Time.current).chronological }
  scope :past, -> { where("starts_at < ?", Time.current).order(starts_at: :desc) }

  def self.search(query, include_attendees: false)
    term = query.to_s.strip
    return all if term.blank?

    pattern = "%#{sanitize_sql_like(term)}%"
    relation = include_attendees ? left_joins(:attendees, :term) : left_joins(:term)
    matches = relation.where(<<~SQL.squish, q: pattern, zone: Time.zone.tzinfo.identifier, clock: "Dy Mon DD HH12:MI AM")
      events.title ILIKE :q OR COALESCE(events.location, '') ILIKE :q
      OR COALESCE(events.notes, '') ILIKE :q OR COALESCE(terms.name, '') ILIKE :q
      OR TO_CHAR(events.starts_at AT TIME ZONE 'UTC' AT TIME ZONE :zone, :clock) ILIKE :q
      OR TO_CHAR(events.starts_at AT TIME ZONE 'UTC' AT TIME ZONE :zone, 'YYYY-MM-DD') ILIKE :q
    SQL
    return matches.distinct unless include_attendees

    matches.or(relation.where(<<~SQL.squish, q: pattern)).distinct
      CONCAT_WS(' ', NULLIF(users.first_name, ''), NULLIF(users.last_name, '')) ILIKE :q
      OR COALESCE(users.email, '') ILIKE :q
    SQL
  end

  def search_fields(include_attendees: false)
    fields = [ title, location, notes, term&.name, clinic_search_clock, starts_at&.in_time_zone&.to_date&.iso8601 ]
    fields.concat(attendees.flat_map { |attendee| [ attendee.display_name, attendee.email ] }) if include_attendees
    fields.compact
  end

  def search_text(include_attendees: false)
    search_fields(include_attendees: include_attendees).join(" ")
  end

  def upcoming?
    starts_at.present? && starts_at >= Time.current
  end

  def attended_by?(user)
    return false if user.blank?
    return attendances.any? { |attendance| attendance.user_id == user.id } if attendances.loaded?

    attendances.exists?(user_id: user.id)
  end

  def rsvped_by?(user)
    return false if user.blank?
    return rsvps.any? { |rsvp| rsvp.user_id == user.id } if rsvps.loaded?

    rsvps.exists?(user_id: user.id)
  end

  private

  def preserve_points_on_update
    return if errors.any?

    # Read the committed credit under a lock, then lock affected members until save commits.
    previous = self.class.lock.find(id)
    remaining = previous.term_id == term_id && previous.category == category ? points : 0
    preserve_point_balances(previous, points: previous.points - remaining, user_ids: previous.attendances.select(:user_id))
  end

  def preserve_points_on_destroy
    previous = self.class.lock.find(id)
    return if preserve_point_balances(previous, points: previous.points, user_ids: previous.attendances.select(:user_id))

    throw :abort
  end

  def assign_term_from_starts_at
    return if starts_at.blank?

    self.term = Term.current(starts_at)
  end

  def clinic_search_clock
    return if starts_at.blank?

    starts_at.in_time_zone.strftime("%a %b %d %I:%M %p")
  end

  def ends_after_start
    return if ends_at.blank? || starts_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after the start")
  end
end
