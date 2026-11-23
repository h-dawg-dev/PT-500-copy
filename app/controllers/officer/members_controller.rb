module Officer
     class MembersController < BaseController
          def index
               @term = Term.current
               @people = User.order(:last_name, :first_name, :email)
               @points_by_user_id = Hash.new(0)
               User.category_points_by_user(@term).each { |(user_id, _category), points| @points_by_user_id[user_id] += points } if @term
          end

          # O14.1: a member's record, with their points this term, the adjustment form and their points history.
          def show
               @member = User.find(params[:id])
               @term = Term.current
               @adjustment = PointAdjustment.new
               @history_term = if params[:history_term_id] == "all"
                    nil
               elsif params[:history_term_id].present?
                    Term.find(params[:history_term_id])
               else
                    @term
               end
               @history = @member.points_history(@history_term)
               @intake_response = @member.latest_questionnaire_response
          end
     end
end
