module Officer
     # O14.3: BaseController sends members and visitors away before any action here runs.
     class PointAdjustmentsController < BaseController
          def create
               @member = User.find(params[:member_id])
               @term = Term.current
               @history_term = @term
               if params.key?(:expected_term_id) && params[:expected_term_id].to_s != @term&.id.to_s
                    redirect_to officer_member_path(@member),
                      alert: "The current semester changed. Review the member's current points before submitting another adjustment.", status: :see_other
                    return
               end
               # O14.4: the adjustment belongs to this member and the current term only.
               @adjustment = PointAdjustment.new(adjustment_params.merge(user: @member, term: @term, recorded_by: current_user))

               # Locked so two officers subtracting at once cannot both pass the check that keeps totals at zero or more.
               if @member.with_lock { @adjustment.save }
                    # O14.1: back to the record, where the total, category progress and history now include the change.
                    redirect_to officer_member_path(@member), notice: saved_notice
               else
                    # O14.2: nothing was saved; show the record again with what to fix.
                    @history = @member.points_history(@term)
                    render "officer/members/show", status: :unprocessable_entity
               end
          end

          private
               def adjustment_params
                    params.require(:point_adjustment).permit(:points, :category, :reason)
               end

               def saved_notice
                    direction = @adjustment.points.positive? ? "to" : "from"
                    "#{helpers.point_change(@adjustment)} #{direction} #{@member.display_name}'s #{@term.name} total."
               end
     end
end
