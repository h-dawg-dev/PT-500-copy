module IntakeForm
     private

          # Shared by the first submission and later updates, which differ only in the page they came from.
          def save_intake_form(submission, form_view, notice)
               answers = Questionnaire.filter_answers(params.fetch(:questionnaire, {}))
            missing = Questionnaire.missing_required(answers)

            if missing.any?
                 @field_errors = missing.to_h { |question| [ question[:key].to_s, [ "This answer is required." ] ] }
              @errors = [ "Please answer every required question." ]
            elsif current_user.save_intake(submission, answers)
                 redirect_to profile_path, notice: notice, status: :see_other
              return
            else
                 @field_errors = submission.errors.to_hash.merge(current_user.errors.to_hash).transform_keys(&:to_s)
              @errors = submission.errors.full_messages + current_user.errors.full_messages
            end

            @questions = Questionnaire::QUESTIONS
            @answers = answers
            render form_view, status: :unprocessable_entity
          end
end
