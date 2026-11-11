# frozen_string_literal: true

describe 'Signing order' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, submitter_count: 2, only_field_types: %w[text]) }
  let(:source) { :api }
  let(:submitters_order) { 'preserved' }
  let(:submission) { create(:submission, :with_submitters, template:, source:, submitters_order:) }
  let(:first_signer) { submission.submitters.find_by!(uuid: template.submitters.first['uuid']) }
  let(:second_signer) { submission.submitters.find_by!(uuid: template.submitters.second['uuid']) }
  let(:awaiting_message) { I18n.t('awaiting_completion_by_the_other_party') }

  def field_values(submitter)
    submitter.submission.template_fields.select { |f| f['submitter_uuid'] == submitter.uuid }
             .to_h { |f| [f['uuid'], 'Jane'] }
  end

  def submit_form(submitter)
    put submit_form_path(slug: submitter.slug), params: { completed: 'true', values: field_values(submitter) }
  end

  def decline_form(submitter)
    post submit_form_decline_index_path(submit_form_slug: submitter.slug), params: { reason: 'Wrong terms' }
  end

  context 'when the submission preserves the signer order' do
    it 'refuses a submit before the signer turn' do
      submit_form(second_signer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => awaiting_message)
      expect(second_signer.reload).to have_attributes(completed_at: nil, values: {})
    end

    it 'shows the awaiting page before the signer turn' do
      get submit_form_path(slug: second_signer.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(awaiting_message)
      expect(response.body).not_to include('<submission-form')
    end

    it 'shows the form once the earlier signer completes' do
      submit_form(first_signer)
      get submit_form_path(slug: second_signer.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<submission-form')
      expect(response.body).not_to include(awaiting_message)
    end

    it 'refuses a decline before the signer turn' do
      decline_form(second_signer)

      expect(response).to redirect_to(submit_form_path(slug: second_signer.slug))
      expect(second_signer.reload.declined_at).to be_nil

      follow_redirect!

      expect(response.body).to include(awaiting_message)
    end

    it 'asks an out-of-turn signer who declines for email verification first' do
      template.update!(preferences: template.preferences.merge('require_email_2fa' => true))

      decline_form(second_signer)
      follow_redirect!

      expect(second_signer.reload.declined_at).to be_nil
      expect(response.body).to include(I18n.t('send_verification_code'))
      expect(response.body).not_to include(awaiting_message)
    end

    it 'reports a completed form before the signer turn' do
      second_signer.update!(completed_at: Time.current)

      submit_form(second_signer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => I18n.t('form_has_been_completed_already'))
    end

    it 'refuses to complete the form through invite before the signer turn' do
      second_signer.update!(values: field_values(second_signer))

      post submit_form_invite_index_path(submit_form_slug: second_signer.slug)

      expect(response).to have_http_status(:unprocessable_content)
      expect(second_signer.reload.completed_at).to be_nil
    end

    it 'lets the next signer submit once the earlier signer completes' do
      submit_form(first_signer)

      expect(response).to have_http_status(:ok)
      expect(first_signer.reload.completed_at).to be_present

      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'lets the next signer decline once the earlier signer completes' do
      submit_form(first_signer)
      decline_form(second_signer)

      expect(response).to redirect_to(submit_form_path(slug: second_signer.slug))
      expect(second_signer.reload.declined_at).to be_present
    end

    it 'lets the first signer decline' do
      decline_form(first_signer)

      expect(response).to redirect_to(submit_form_path(slug: first_signer.slug))
      expect(first_signer.reload.declined_at).to be_present
    end

    it 'does not hold back a signer who has no place in the order' do
      submission.update!(template_submitters: submission.template_submitters.map do |item|
        item['uuid'] == second_signer.uuid ? item.merge('uuid' => SecureRandom.uuid) : item
      end)

      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end
  end

  context 'when the submission does not preserve the signer order' do
    let(:submitters_order) { 'random' }

    it 'lets a later signer submit first' do
      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'lets a later signer decline first' do
      decline_form(second_signer)

      expect(response).to redirect_to(submit_form_path(slug: second_signer.slug))
      expect(second_signer.reload.declined_at).to be_present
    end

    it 'shows a later signer the form' do
      get submit_form_path(slug: second_signer.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<submission-form')
    end

    context 'when the account enforces the signing order' do
      before { create(:account_config, account:, key: AccountConfig::ENFORCE_SIGNING_ORDER_KEY, value: true) }

      it 'holds a later signer on the awaiting page and refuses the submit' do
        get submit_form_path(slug: second_signer.slug)

        expect(response.body).to include(awaiting_message)

        submit_form(second_signer)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq('error' => awaiting_message)
        expect(second_signer.reload.completed_at).to be_nil
      end
    end
  end

  context 'with a single signer' do
    let(:template) { create(:template, account:, author:, submitter_count: 1, only_field_types: %w[text]) }

    it 'lets the signer submit' do
      submit_form(first_signer)

      expect(response).to have_http_status(:ok)
      expect(first_signer.reload.completed_at).to be_present
    end
  end

  context 'when the signer started the form from a shared link' do
    let(:source) { :link }

    it 'lets a later party submit first' do
      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'refuses a later party when the template preserves the signer order' do
      template.update!(preferences: template.preferences.merge('submitters_order' => 'preserved'))

      submit_form(second_signer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => awaiting_message)
    end
  end
end
