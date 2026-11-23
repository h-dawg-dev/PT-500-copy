class AnnouncementDismissalsController < ApplicationController
     before_action :require_authentication

     # U12.2: marks the changes the pop-up showed as seen, so it does not appear again. Only the ids
     # that were shown, so a change saved while the pop-up was open still gets its own announcement.
     # U12.3: scoped to the signed-in member, so nobody can mark another member's changes.
     def create
          ids = params.permit(point_adjustment_ids: []).fetch(:point_adjustment_ids, [])
          current_user.point_adjustments.unseen.where(id: ids).update_all(seen_at: Time.current)

          respond_to do |format|
               format.json { head :no_content }
               format.html { redirect_back_or_to root_path }
          end
     end
end
