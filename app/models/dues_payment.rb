class DuesPayment < ApplicationRecord
     belongs_to :user
  belongs_to :term
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :user_id, uniqueness: { scope: :term_id }
  validate :user_owes_dues

  private

       # Officers pay no dues, so a payment can't be recorded for one.
       def user_owes_dues
            errors.add(:user, "is an officer and does not pay dues") if user && !user.owes_dues?
       end
end
