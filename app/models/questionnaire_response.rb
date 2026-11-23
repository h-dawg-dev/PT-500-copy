class QuestionnaireResponse < ApplicationRecord
     belongs_to :user, optional: true

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_validation :normalize_email

  # A response belongs to a signed-in member. Older submissions were made
  # before sign-in was required, so an unclaimed row with the same normalized
  # email still counts as completed for that account.
  scope :completed_for, ->(user) {
    where(user_id: user.id).or(where(user_id: nil, email: user.email))
  }

  def self.completed_for?(user)
    return false if user.blank?

    completed_for(user).exists?
  end

  def self.latest_for(user)
    return if user.blank?

    completed_for(user).order(created_at: :desc).first
  end

  # The signed-in user if there was one, otherwise a best-guess match on the typed email.
  def matched_user
       user || User.find_by(email: email)
  end

  private

       def normalize_email
            self.email = email.to_s.strip.downcase.presence
       end
end
