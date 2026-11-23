module PointBalanceProtection
     private

          def preserve_point_balances(event, points:, user_ids:)
               return true unless points.positive? && event.term

               # Every credit-removing path locks event first, then members in id order.
               # Deductions use the same member locks, so concurrent changes cannot spend the same credit.
               members = User.earning_points.where(id: user_ids).order(:id).lock.to_a
               return true if members.empty?

               balances = User.category_points_by_user(event.term)
               members.each do |member|
                    next if balances.fetch([ member.id, event.category ], 0) >= points

                    errors.add(:base, "This change would leave #{member.display_name}'s #{event.category} points below zero for #{event.term.name}. Reverse or offset deductions before removing this credit.")
               end
               errors.empty?
          end
end
