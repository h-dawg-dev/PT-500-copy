# Returns one account to a just-signed-up state so it can be demoed again: the intake form
# shows on the next sign-in. The user row and its Clerk link stay, so the person signs in as
# usual. Run through `bin/rails "users:reset_for_demo[EMAIL]"`.
class DemoAccountReset
     PROFILE_COLUMNS = %w[ major tshirt_size class_year ].freeze
     # Adjustments go before check-ins: removing a check-in is refused while a deduction depends on it.
     RECORDS = %i[ rsvps point_adjustments attendances dues_payments ].freeze

     attr_reader :user

     def initialize(user, officer: false)
          @user = user
          @officer = officer
     end

     # What a reset would remove, for the dry run.
     def summary
          counts = RECORDS.index_with { |name| user.public_send(name).count }
          { intake_responses: intake_responses.count }.merge(counts, profile: user.attributes.slice(*PROFILE_COLUMNS))
     end

     def call
          User.transaction do
               # Includes an unclaimed response under the same email, which also counts as completed.
               intake_responses.delete_all
               RECORDS.each { |name| user.public_send(name).each(&:destroy!) }
               user.assign_attributes(PROFILE_COLUMNS.index_with(nil))
               user.role = :officer if @officer
               user.save!
          end
          user.reload
     end

     private

     def intake_responses
          QuestionnaireResponse.completed_for(user)
     end
end
