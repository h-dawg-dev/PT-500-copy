# An officer's correction to one member's points for one term, such as credit for a member
# who attended but was never checked in. Points are signed: a negative number subtracts.
class PointAdjustment < ApplicationRecord
     REASON_MAX_LENGTH = 500

     belongs_to :user
     belongs_to :term, optional: true
     belongs_to :recorded_by, class_name: "User", optional: true

     enum :category, Event.categories, validate: { allow_nil: true }

     # O14.2: a whole, non-zero amount and a category are required. O14.1 asks for a reason, so it is required too.
     validates :points, presence: true
     validates :points, numericality: { only_integer: true, other_than: 0, in: -Event::MAX_POINTS..Event::MAX_POINTS }, allow_nil: true
     validates :category, presence: true
     validates :reason, presence: true, length: { maximum: REASON_MAX_LENGTH }
     # O14.4: an adjustment always belongs to a term.
     validate :term_is_set
     # O14.3: officers cannot be given points.
     validate :user_earns_points
     validate :category_total_stays_at_or_above_zero, on: :create

     normalizes :reason, with: ->(reason) { reason.strip }
     before_validation :lock_member_for_deduction, on: :create

     # O14.4: a term, or nil for all time.
     scope :for_period, ->(term) { term ? where(term_id: term.id) : all }
     # U12.1, U12.2: changes the member has not yet dismissed in the pop-up.
     scope :unseen, -> { where(seen_at: nil) }

     private
          def lock_member_for_deduction
               self.user = User.lock.find(user_id) if user_id && points.is_a?(Integer) && points.negative?
          end

          def term_is_set
               return if term.present?

               errors.add(:base, "No term covers today, so there is no current semester to adjust. Ask an administrator to set the term dates.")
          end

          # O14.3: officers sit outside the points system, so nothing can be added to or taken from them.
          def user_earns_points
               return if user.nil? || user.earns_points?

               errors.add(:base, "Officers are not part of the points system, so they can't be given points.")
          end

          def category_total_stays_at_or_above_zero
               return unless user&.earns_points? && term && category.present? && points.is_a?(Integer) && points.negative?

               available = user.points_by_category(term).fetch(category)
               return if available + points >= 0

               message = if available.positive?
                    "#{user.display_name} has only #{available} #{category} #{"point".pluralize(available)} in #{term.name}, so you can subtract at most #{available}."
               else
                    "#{user.display_name} has no #{category} points in #{term.name} to subtract."
               end
               errors.add(:base, message)
          end
end
