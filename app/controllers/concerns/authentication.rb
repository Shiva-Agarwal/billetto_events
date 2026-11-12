# Clerk-backed authentication. The session JWT comes from the `__session` cookie (same-origin
# browser requests, set by clerk-js) or an `Authorization: Bearer` header (API clients).
# Verification failures are treated as "signed out" - we fail closed.
module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_session, :current_user_id, :signed_in?, :clerk
  end

  private

  def current_session
    return @current_session if defined?(@current_session)

    @current_session = authenticate_from_token
  end

  def current_user_id = current_session&.user_id

  def signed_in? = current_session.present?

  def require_authentication!
    return if signed_in?

    respond_to do |format|
      format.html { redirect_to sign_in_path(redirect_url: request.referer.presence), alert: t("votes.unauthenticated"), status: :see_other }
      format.json { render json: { error: "unauthenticated" }, status: :unauthorized }
      format.any { head :unauthorized }
    end
  end

  def clerk = Rails.configuration.clerk

  def authenticate_from_token
    token = bearer_token || cookies[ClerkAuth::SESSION_COOKIE]
    return if token.blank?

    clerk.verify_session_token(token)
  rescue ClerkAuth::InvalidToken => e
    Rails.logger.info("[auth] rejected session token: #{e.message}")
    nil
  rescue ClerkAuth::ConnectionError => e
    Rails.logger.error("[auth] could not verify session token: #{e.message}")
    nil
  end

  def bearer_token
    request.authorization.to_s[/\ABearer (.+)\z/, 1].presence
  end
end
