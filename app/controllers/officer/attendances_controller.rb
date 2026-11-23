module Officer
  class AttendancesController < BaseController
    def create
      event = Event.find(params[:event_id])
      member = User.find(params[:user_id])
      attendance = event.attendances.find_or_initialize_by(user: member)
      attendance.recorded_by = current_user

      if attendance.save
        respond_to do |format|
          format.json { render json: attendance_payload(event, member, attendance, present: true) }
          format.html { redirect_to officer_event_path(event), notice: "#{member.display_name} is marked present." }
        end
      else
        respond_to do |format|
          format.json { render json: { error: "Could not mark #{member.display_name} present." }, status: :unprocessable_entity }
          format.html { redirect_to officer_event_path(event), alert: "Could not mark #{member.display_name} present." }
        end
      end
    end

    def destroy
      event = Event.find(params[:event_id])
      attendance = event.attendances.find_by(id: params[:id])
      member = attendance&.user
      if attendance && !attendance.destroy
        message = attendance.errors.full_messages.to_sentence
        respond_to do |format|
          format.json { render json: { error: message }, status: :unprocessable_entity }
          format.html { redirect_to officer_event_path(event), alert: message, status: :see_other }
        end
        return
      end

      respond_to do |format|
        format.json { render json: attendance_payload(event, member, nil, present: false) }
        format.html { redirect_to officer_event_path(event), notice: "#{member&.display_name || "That person"} is no longer marked present." }
      end
    end

    private

    def attendance_payload(event, member, attendance, present:)
      {
        present: present,
        attendance_id: attendance&.id,
        points_awarded: attendance&.points_awarded,
        user_id: member&.id,
        name: member&.display_name,
        present_count: event.attendances.count
      }
    end
  end
end
