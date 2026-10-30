# frozen_string_literal: true

# The platform's sign-in hand-off (PlatformSessions): a valid token signs its person in to their tenant's account, in a
# fresh session, and lands on `next`; a refusal is a page that sends them back to the platform.
class PlatformSessionsController < ApplicationController
  skip_before_action :maybe_redirect_to_setup
  skip_before_action :authenticate_user!
  skip_authorization_check

  def show
    return render 'errors/404', status: :not_found, layout: false if Docuseal.platform_api_token.blank?

    user = PlatformSessions.user_for!(PlatformSessions.verify!(params[:token]))

    reset_session
    sign_in(user)

    redirect_to PlatformSessions.next_path(params[:next])
  rescue PlatformSessions::Refused => e
    render :error, status: e.status, locals: { reason: e.status }
  end
end
