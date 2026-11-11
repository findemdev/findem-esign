# frozen_string_literal: true

# Records a signer's acceptance of the account's electronic records disclosure, once per version and text.
class SubmitFormConsentController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  def create
    submitter = Submitter.find_by!(slug: params[:submit_form_slug])

    return head :unprocessable_content unless can_accept?(submitter)

    consent = Submitters.signing_consent(submitter.account)

    if consent.nil? || consent.values_at('version', 'sha256') != [params[:version], params[:sha256]]
      return render json: { error: I18n.t('the_disclosure_has_changed_refresh_the_page') },
                    status: :unprocessable_content
    end

    unless Submitters.consent_accepted?(submitter, consent)
      SubmissionEvents.create_with_tracking_data(submitter, 'accept_consent', request,
                                                 { version: consent['version'], sha256: consent['sha256'] })
    end

    head :ok
  end

  private

  def can_accept?(submitter)
    !submitter.declined_at? &&
      !submitter.completed_at? &&
      !submitter.submission.archived_at? &&
      !submitter.submission.expired? &&
      !submitter.submission.template&.archived_at? &&
      !submitter.viewer? &&
      Submitters::AuthorizedForForm.call(submitter, current_user, request)
  end
end
