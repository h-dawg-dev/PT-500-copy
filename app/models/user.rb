class User < ApplicationRecord
  REQUIRED_POINTS = 7
  REQUIRED_CATEGORY_POINTS = { "professional" => 1, "social" => 1 }.freeze
  ORGANIZATION_MEMBER_EMAIL = "ptsocietytamu@gmail.com".freeze
  EMAIL_DOMAIN_MESSAGE = "Use a verified @tamu.edu email address or the authorized organization account.".freeze

  # Checked on every Clerk sync, including existing accounts and officer requests.
  class EmailDomainNotAllowed < StandardError; end

  enum :role, { member: 0, officer: 1 }, default: :member, validate: true

  has_many :attendances, dependent: :destroy
  has_many :attended_events, through: :attendances, source: :event
  has_many :created_events, class_name: "Event", foreign_key: :created_by_id, dependent: :nullify
  has_many :rsvps, dependent: :destroy
  has_many :rsvped_events, through: :rsvps, source: :event
  has_many :questionnaire_responses, dependent: :nullify
  has_many :point_adjustments, dependent: :destroy
  has_many :dues_payments, dependent: :destroy

  # Intake form answers that are copied onto the member's account.
  PROFILE_FIELDS = %i[ major tshirt_size ].freeze
  TSHIRT_SIZES = %w[ XS S M L XL 2XL 3XL ].freeze
  MAJOR_MAX_LENGTH = 100

  validates :clerk_user_id, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validate :organization_account_stays_member

  # Both optional, and checked only when the intake form is saved. sync_from_clerk must keep
  # saving these accounts on every request.
  with_options on: :profile do
    validates :major, length: { maximum: MAJOR_MAX_LENGTH }
    validates :tshirt_size, inclusion: { in: TSHIRT_SIZES, message: "is not a listed size", allow_blank: true }
  end

  normalizes :major, with: ->(major) { major.squish }

  # Officers run the sessions, so they sit outside the points system: their attendance is
  # still recorded, but it is worth nothing and they are left off points lists and reports.
  # Points are worked out from attendance and adjustments each time, so this follows the
  # person's current role.
  scope :earning_points, -> { member }

  before_validation :normalize_email

  # Points per [user id, category] for a term, or all time when term is nil: session points
  # plus adjustments, in two grouped queries. Callers skip people who don't earn points.
  def self.category_points_by_user(term)
    checkins = Attendance.joins(:event)
    checkins = checkins.where(events: { term_id: term.id }) if term
    totals = checkins.group(:user_id, "events.category").sum("events.points")
    PointAdjustment.for_period(term).group(:user_id, :category).sum(:points).each do |key, points|
      totals[key] = totals.fetch(key, 0) + points
    end
    totals
  end

  def self.officer_emails
    ENV.fetch("OFFICER_EMAILS", "").split(",").map { |email| email.strip.downcase }.reject(&:blank?)
  end

  def self.officer_email?(email)
    return false if email.blank?
    return false if organization_member_email?(email)

    officer_emails.include?(email.to_s.strip.downcase)
  end

  # The student address the society uses. Do not widen this to every
  # *.tamu.edu subdomain without asking the customer, because some of those
  # domains belong to departments and affiliates rather than students.
  def self.tamu_email?(email)
    normalized = email.to_s.strip.downcase
    valid_login_email?(normalized) && normalized.split("@").last == "tamu.edu"
  end

  # With the @tamu.edu requirement switched off in Society settings, any
  # syntactically valid verified address is accepted (the caller checks verification).
  def self.email_allowed_for_signup?(email)
    return valid_login_email?(email.to_s.strip.downcase) unless AppSetting.require_tamu_email?

    tamu_email?(email) || organization_member_email?(email)
  end

  def self.organization_member_email?(email)
    email.to_s.strip.downcase == ORGANIZATION_MEMBER_EMAIL
  end

  def self.valid_login_email?(email)
    return false unless URI::MailTo::EMAIL_REGEXP.match?(email)

    local = email.split("@", 2).first
    !local.start_with?(".") && !local.end_with?(".") && !local.include?("..")
  end

  def self.email_from_clerk_user(clerk_user)
    return if clerk_user.nil?

    emails = Array(clerk_user.try(:email_addresses))
    primary_id = clerk_user.try(:primary_email_address_id)
    return if primary_id.blank?

    primary = emails.find { |entry| entry.try(:id).to_s == primary_id.to_s }
    return unless primary&.try(:verification)&.try(:status).to_s == "verified"

    primary.email_address.presence
  end

  def self.sync_from_clerk(attrs)
    attrs = attrs.to_h.symbolize_keys
    clerk_user_id = attrs[:clerk_user_id].presence
    return if clerk_user_id.blank?
    unless attrs[:email_verified] == true && email_allowed_for_signup?(attrs[:email])
      raise EmailDomainNotAllowed, EMAIL_DOMAIN_MESSAGE
    end

    user = find_or_initialize_by(clerk_user_id: clerk_user_id)
    user.email = attrs[:email] if attrs[:email].present?
    user.first_name = attrs[:first_name] if attrs.key?(:first_name)
    user.last_name = attrs[:last_name] if attrs.key?(:last_name)

    if user.organization_member_account?
      user.role = :member
    elsif user.new_record?
      user.role = officer_email?(user.email) ? :officer : :member
    elsif user.member? && officer_email?(user.email)
      user.role = :officer
    end

    user.save!
    user
  end

  def display_name
    name = [ first_name, last_name ].map(&:presence).compact.join(" ")
    name.presence || email
  end

  def organization_member_account?
    self.class.organization_member_email?(email)
  end

  def earns_points?
    member?
  end

# Officers pay no dues, the same way they earn no points.
def owes_dues?
  member?
end

# Dues are tracked per term, so a new term starts unpaid with nothing to reset.
def dues_paid?(term = Term.current)
  owes_dues? && term.present? && dues_payments.exists?(term_id: term.id)
end

  def questionnaire_completed?
    QuestionnaireResponse.completed_for?(self)
  end

  def latest_questionnaire_response
    QuestionnaireResponse.latest_for(self)
  end

  # The saved intake form, with the account's copy of the fields it shares.
  def intake_answers
    (latest_questionnaire_response&.answers || {}).merge(attributes.slice(*PROFILE_FIELDS.map(&:to_s)).compact)
  end

  # Saves the form and the answers copied onto the account together, or neither.
  # A first submission keeps anything already on the account for a question the member
  # skipped; after that the form shows the saved values, so a blank answer clears them.
  def save_intake(submission, answers)
    fields = PROFILE_FIELDS.to_h { |field| [ field, answers[field.to_s] ] }
    assign_attributes(submission.new_record? ? fields.compact : fields)
    submission.assign_attributes(user: self, email: answers["email"].presence || email, questions: Questionnaire::QUESTIONS, answers: answers)

    saved = false
    transaction do
      saved = save(context: :profile) && submission.save
      raise ActiveRecord::Rollback unless saved
    end
    saved
  end

  def points_earned(term = :current)
    points_by_category(term).values.sum
  end

  # O14.1, O14.4: session points plus officer adjustments, per category, for one term.
  def points_by_category(term = :current)
    totals = Hash.new(0)
    if earns_points?
      attended_events_for(term).group(:category).sum(:points).each { |category, points| totals[category] += points }
      point_adjustments_for(term).group(:category).sum(:points).each { |category, points| totals[category] += points }
    end
    Event.categories.keys.index_with { |category| totals[category] }
  end

  def missing_category_points(term = :current)
    earned = points_by_category(term)
    required_category_points_for(term).to_h { |category, required| [ category, [ required - earned[category], 0 ].max ] }
  end

  def required_points_for(term = :current)
    resolve_term(term)&.required_points || REQUIRED_POINTS
  end

  def points_requirement_met?(term = :current)
    return false if term == :current && Term.current.nil?

    points_earned(term) >= required_points_for(term) && missing_category_points(term).values.all?(&:zero?)
  end

  # O14.1: the points history. Check-ins and adjustments together, newest first. A nil term means all time.
  def points_history(term = :current, limit: nil)
    resolved = resolve_term(term)
    return [] if term == :current && resolved.nil?

    checkins = attendances.includes(:event).order(created_at: :desc).limit(limit)
    checkins = checkins.joins(:event).where(events: { term_id: resolved.id }) if resolved
    adjustments = point_adjustments.for_period(resolved).includes(:recorded_by).order(created_at: :desc).limit(limit)
    entries = (checkins.to_a + adjustments.to_a).sort_by(&:created_at).reverse
    limit ? entries.first(limit) : entries
  end

  private

  def organization_account_stays_member
    if organization_member_account? && !member?
      errors.add(:role, "must remain member for the organization account")
    end
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def resolve_term(term)
    term == :current ? Term.current : term
  end

  def attended_events_for(term)
    resolved = resolve_term(term)
    return attended_events.none if term == :current && resolved.nil?

    resolved ? attended_events.where(term_id: resolved.id) : attended_events
  end

  def point_adjustments_for(term)
    resolved = resolve_term(term)
    return point_adjustments.none if term == :current && resolved.nil?

    point_adjustments.for_period(resolved)
  end

  def required_category_points_for(term)
    resolved = resolve_term(term)
    resolved ? resolved.required_category_points : REQUIRED_CATEGORY_POINTS
  end
end
