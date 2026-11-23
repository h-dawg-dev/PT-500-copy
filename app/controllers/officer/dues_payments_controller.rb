module Officer
     class DuesPaymentsController < BaseController
          before_action :load_member_and_term

       # U30.3: any officer can record this term's dues for one member.
       def create
            payment = @member.dues_payments.find_or_initialize_by(term: @term)
            payment.recorded_by = current_user if payment.new_record?

            if payment.save
                 redirect_to officer_member_path(@member), notice: "#{@member.display_name} is marked as having paid #{@term.name} dues."
            else
                 redirect_to officer_member_path(@member), alert: payment.errors.full_messages.to_sentence
            end
          rescue ActiveRecord::RecordNotUnique
               redirect_to officer_member_path(@member), notice: "#{@member.display_name} is already marked as having paid #{@term.name} dues."
       end

       # Undo a mistake. Only this member's row for this term is removed.
       def destroy
            @member.dues_payments.where(term_id: @term.id).destroy_all
         redirect_to officer_member_path(@member), notice: "#{@member.display_name} is no longer marked as having paid #{@term.name} dues."
       end

       private

            # The page sends the term it showed, so a submit after the semester rolls over changes nothing.
            def load_member_and_term
                 @member = User.find(params[:member_id])
              @term = Term.current
              return if @term && params[:expected_term_id].to_s == @term.id.to_s

              redirect_to officer_member_path(@member), alert: "The semester changed or no semester is active. Nothing was changed."
            end
     end
end
