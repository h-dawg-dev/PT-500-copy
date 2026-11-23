module Officer
     class AttendanceImportsController < BaseController
          MAX_SHOWN_ERRORS = 10

       def create
            event = Event.find(params[:event_id])
         result = AttendanceImport.new(file: params[:file], event: event, officer: current_user).call

         if result.success?
              redirect_to officer_event_path(event),
                          notice: "Marked #{result.created_count} present; #{result.skipped_count} already recorded."
         else
              redirect_to officer_event_path(event), flash: { import_errors: errors_for_flash(result.errors) }
         end
       end

       private

            # The flash lives in the session cookie, so keep the list short.
            def errors_for_flash(errors)
                 shown = errors.first(MAX_SHOWN_ERRORS).map { |error| error.truncate(120) }
              hidden = errors.size - shown.size
              shown << "...and #{hidden} more." if hidden.positive?
              shown
            end
     end
end
