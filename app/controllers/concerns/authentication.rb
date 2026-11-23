module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?, :clerk_configured?, :clerk_sign_in_url,
      :signup_restricted?, :questionnaire_completed?
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = if clerk&.session
      User.sync_from_clerk(clerk_user_attributes)
    end
  rescue User::EmailDomainNotAllowed
    # The Clerk session is valid but its email does not meet the access policy.
    # Keep the signed-out state and show the restriction page instead of
    # retrying on every helper call.
    @signup_restricted = true
    @current_user = nil
  end

  def signed_in?
    current_user.present?
  end

  def signup_restricted?
    @signup_restricted == true
  end

  # One intake response per member. Unclaimed legacy responses with the same
  # email count too, so members who filled the old public form are not asked
  # again. Memoized because the header and dashboard both ask.
  def questionnaire_completed?
    return @questionnaire_completed if defined?(@questionnaire_completed)

    @questionnaire_completed = signed_in? && current_user.questionnaire_completed?
  end

  def clerk_configured?
    ENV["CLERK_PUBLISHABLE_KEY"].to_s.start_with?("pk_") &&
      ENV["CLERK_SECRET_KEY"].to_s.start_with?("sk_") &&
      ENV["CLERK_SIGN_IN_URL"].present?
  end

  def clerk_sign_in_url
    base = ENV["CLERK_SIGN_IN_URL"].presence
    return if base.blank?
    return base unless respond_to?(:request) && request

    origin = request.base_url
    uri = URI.parse(base)
    reserved = %w[redirect_url sign_in_force_redirect_url sign_up_force_redirect_url]
    params = URI.decode_www_form(String(uri.query)).reject { |key, _| reserved.include?(key) }
    params << [ "redirect_url", origin ]
    params << [ "sign_in_force_redirect_url", origin ]
    params << [ "sign_up_force_redirect_url", origin ]
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  def require_authentication
    return if signed_in?

    if clerk_sign_in_url.present?
      redirect_to clerk_sign_in_url, allow_other_host: true, alert: "Please sign in."
    else
      redirect_to root_path, alert: "Please sign in."
    end
  end

  def require_officer
    return if current_user&.officer? && !current_user.organization_member_account?

    redirect_to root_path, alert: "That area is for officers."
  end

  private

  def clerk_user_attributes
    clerk_user = clerk.user
    verified_email = User.email_from_clerk_user(clerk_user)
    {
      clerk_user_id: clerk.user_id,
      email: verified_email,
      email_verified: verified_email.present?,
      first_name: clerk_user&.first_name,
      last_name: clerk_user&.last_name
    }
  end
end
