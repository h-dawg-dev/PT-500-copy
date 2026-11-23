class ApplicationController < ActionController::Base
  include Clerk::Authenticatable
  include Authentication

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :enforce_signup_policy

  helper_method :point_announcements

  private

  # Resolve the Clerk session once so an account blocked by the email access
  # rule gets an explanation instead of a redirect loop through sign-in.
  def enforce_signup_policy
    current_user
    render "application/signup_restricted", status: :forbidden if signup_restricted?
  end

  # U12.1: officer changes to the signed-in member's points that they have not dismissed yet, oldest first.
  # U12.3: always the signed-in member's own changes, never anyone else's.
  def point_announcements
    return [] unless current_user&.earns_points?

    @point_announcements ||= current_user.point_adjustments.unseen.order(:created_at, :id).to_a
  end
end
