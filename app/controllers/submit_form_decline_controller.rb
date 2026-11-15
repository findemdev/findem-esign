# frozen_string_literal: true

class SubmitFormDeclineController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  before_action :load_submitter
  before_action :maybe_refuse_out_of_turn

  def create
    return redirect_to submit_form_path(@submitter.slug) if declining_disabled? ||
                                                            @submitter.declined_at? ||
                                                            @submitter.completed_at? ||
                                                            @submitter.submission.archived_at? ||
                                                            @submitter.submission.expired? ||
                                                            @submitter.submission.template&.archived_at? ||
                                                            @submitter.viewer? ||
                                                            !Submitters::AuthorizedForForm.call(@submitter,
                                                                                                current_user,
                                                                                                request)

    ApplicationRecord.transaction do
      @submitter.update!(declined_at: Time.current, values: @submitter.preferences['default_values'] || {})

      SubmissionEvents.create_with_tracking_data(@submitter, 'decline_form', request, { reason: params[:reason] })

      maybe_withdraw_consent
    end

    user = @submitter.submission.created_by_user || @submitter.template.author

    if Users.send_emails?(user) &&
       user.user_configs.find_by(key: UserConfig::RECEIVE_DECLINED_EMAIL)&.value != false
      SubmitterMailer.declined_email(@submitter, user).deliver_later!
    end

    WebhookUrls.enqueue_events(@submitter, 'form.declined')

    redirect_to submit_form_path(@submitter.slug)
  end

  private

  def maybe_withdraw_consent
    return if params[:withdraw_consent] != '1'

    consent = Submitters.signing_consent(@submitter.account)

    return unless consent

    SubmissionEvents.create_with_tracking_data(@submitter, 'withdraw_consent', request,
                                               Submitters.consent_event_data(consent))
  end

  def declining_disabled?
    @submitter.account.account_configs.find_by(key: AccountConfig::ALLOW_TO_DECLINE_KEY)&.value == false
  end

  def load_submitter
    @submitter = Submitter.find_by!(slug: params[:submit_form_slug])
  end

  def maybe_refuse_out_of_turn
    return if Submitters::AuthorizedForForm.pass_signing_turn?(@submitter)

    # The form page runs its verification steps first, then shows the awaiting page.
    redirect_to submit_form_path(@submitter.slug)
  end
end
