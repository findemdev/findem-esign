# frozen_string_literal: true

describe 'Signing order' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:submitter_count) { 2 }
  let(:template) { create(:template, account:, author:, submitter_count:, only_field_types: %w[text]) }
  let(:submitters_order) { 'preserved' }
  let(:submission) do
    create(:submission, :with_submitters, template:, source: :invite, submitters_order:, created_by_user: author)
  end
  let(:first_signer) { signer(0) }
  let(:second_signer) { signer(1) }
  let(:awaiting_message) { I18n.t('awaiting_completion_by_the_other_party') }

  def signer(index)
    submission.submitters.find_by!(uuid: template.submitters[index]['uuid'])
  end

  def field_values(submitter)
    submitter.submission.template_fields.select { |f| f['submitter_uuid'] == submitter.uuid }
             .to_h { |f| [f['uuid'], 'Jane'] }
  end

  def open_form(submitter)
    get submit_form_path(slug: submitter.slug)

    expect(response).to have_http_status(:ok)

    response.body
  end

  def submit_form(submitter)
    put submit_form_path(slug: submitter.slug), params: { completed: 'true', values: field_values(submitter) }
  end

  def decline_form(submitter)
    post submit_form_decline_index_path(submit_form_slug: submitter.slug), params: { reason: 'Wrong terms' }
  end

  def invite_form(submitter)
    submitter.update!(values: field_values(submitter))

    post submit_form_invite_index_path(submit_form_slug: submitter.slug)
  end

  # The "Send email" button on the submission page.
  def send_email_early(submitter)
    sign_in(author)
    post submitter_send_email_index_path(submitter)

    expect(submitter.reload.sent_at).to be_present
    expect(SendSubmitterInvitationEmailJob.jobs.map { |job| job['args'].first['submitter_id'] }).to eq([submitter.id])

    sign_out(author)
  end

  # An API send without `order`, which preserves the order; the integrator hands out each embed_src link.
  def create_api_submission
    post '/api/submissions',
         headers: { 'x-auth-token': author.access_token.token, 'Content-Type' => 'application/json' },
         params: { template_id: template.id, send_email: false,
                   submitters: [{ role: 'First Party', email: 'first.party@example.com' },
                                { role: 'Second Party', email: 'second.party@example.com' }] }.to_json

    expect(response).to have_http_status(:ok)
    expect(Submission.last).to be_submitters_order_preserved

    response.parsed_body.to_h { |item| [item['role'], URI(item['embed_src']).path] }
  end

  def enforce_order_on_template
    template.update!(preferences: template.preferences.merge('submitters_order' => 'preserved'))
  end

  def enforce_order_on_account
    create(:account_config, account:, key: AccountConfig::ENFORCE_SIGNING_ORDER_KEY, value: true)
  end

  shared_examples 'an enforced signing order' do
    it 'holds a later party on the awaiting page, also for Sign in person' do
      body = open_form(second_signer)

      expect(body).to include(awaiting_message)
      expect(body).not_to include('<submission-form')

      sign_in(author)
      body = open_form(second_signer)

      expect(body).to include(awaiting_message)
      expect(body).not_to include('<submission-form')
    end

    it 'refuses a submit before the party turn' do
      submit_form(second_signer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => awaiting_message)
      expect(second_signer.reload).to have_attributes(completed_at: nil, values: {})
    end

    it 'refuses a decline before the party turn' do
      decline_form(second_signer)

      expect(response).to redirect_to(submit_form_path(slug: second_signer.slug))
      expect(second_signer.reload.declined_at).to be_nil

      follow_redirect!

      expect(response.body).to include(awaiting_message)
    end

    it 'asks an out-of-turn party who declines for email verification first' do
      template.update!(preferences: template.preferences.merge('require_email_2fa' => true))

      decline_form(second_signer)
      follow_redirect!

      expect(second_signer.reload.declined_at).to be_nil
      expect(response.body).to include(I18n.t('send_verification_code'))
      expect(response.body).not_to include(awaiting_message)
    end

    it 'reports a completed form before the party turn' do
      second_signer.update!(completed_at: Time.current)

      submit_form(second_signer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => I18n.t('form_has_been_completed_already'))
    end

    it 'refuses to complete the form through invite before the party turn' do
      invite_form(second_signer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(second_signer.reload.completed_at).to be_nil
    end

    it 'holds a later party sent an early email on the awaiting page' do
      send_email_early(second_signer)

      expect(open_form(second_signer)).to include(awaiting_message)

      submit_form(second_signer)

      expect(response).to have_http_status(:unprocessable_content)

      decline_form(second_signer)

      expect(second_signer.reload).to have_attributes(completed_at: nil, declined_at: nil)
    end

    it 'holds a later party who opens an API link on the awaiting page' do
      links = create_api_submission

      get links.fetch('Second Party')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(awaiting_message)
      expect(response.body).not_to include('<submission-form')
    end

    it 'lets the next party sign once the earlier party completes' do
      submit_form(first_signer)

      expect(response).to have_http_status(:ok)
      expect(open_form(second_signer)).to include('<submission-form')

      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'lets the next party decline once the earlier party completes' do
      submit_form(first_signer)
      decline_form(second_signer)

      expect(response).to redirect_to(submit_form_path(slug: second_signer.slug))
      expect(second_signer.reload.declined_at).to be_present
    end

    it 'lets the first party decline' do
      decline_form(first_signer)

      expect(response).to redirect_to(submit_form_path(slug: first_signer.slug))
      expect(first_signer.reload.declined_at).to be_present
    end

    it 'does not hold back a party who has no place in the order' do
      submission.update!(template_submitters: submission.template_submitters.map do |item|
        item['uuid'] == second_signer.uuid ? item.merge('uuid' => SecureRandom.uuid) : item
      end)

      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end
  end

  context 'when only the submission preserves the order' do
    it 'shows a later party the form before the earlier party signs' do
      body = open_form(second_signer)

      expect(body).to include('<submission-form')
      expect(body).not_to include(awaiting_message)
    end

    it 'lets a later party submit before the earlier party' do
      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'lets a later party decline before the earlier party' do
      decline_form(second_signer)

      expect(response).to redirect_to(submit_form_path(slug: second_signer.slug))
      expect(second_signer.reload.declined_at).to be_present
    end

    it 'lets a later party complete through invite before the earlier party' do
      invite_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'opens a later party form for Sign in person' do
      sign_in(author)
      body = open_form(second_signer)

      expect(body).to include('<submission-form')
      expect(body).not_to include(awaiting_message)

      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'lets a later party sent an early email sign from the link' do
      send_email_early(second_signer)

      expect(open_form(second_signer)).to include('<submission-form')

      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'lets a later party sign from an API link handed out with the others' do
      links = create_api_submission
      later_party = Submitter.find_by!(slug: links.fetch('Second Party').split('/').last)

      get links.fetch('Second Party')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<submission-form')

      submit_form(later_party)

      expect(response).to have_http_status(:ok)
      expect(later_party.reload.completed_at).to be_present
    end
  end

  context 'when the template preserves the signer order' do
    before { enforce_order_on_template }

    it_behaves_like 'an enforced signing order'
  end

  context 'when the account enforces the signing order' do
    before { enforce_order_on_account }

    it_behaves_like 'an enforced signing order'
  end

  context 'with three parties and the second sent an early email' do
    let(:submitter_count) { 3 }
    let(:third_signer) { signer(2) }

    before do
      create(:encrypted_config, account:, key: EncryptedConfig::ESIGN_CERTS_KEY,
                                value: GenerateCertificate.call.transform_values(&:to_pem))
    end

    # The parties the completion chain emails once the first party signs.
    def run_completion_chain
      send_email_early(second_signer)
      SendSubmitterInvitationEmailJob.clear

      submit_form(first_signer)

      expect(response).to have_http_status(:ok)

      ProcessSubmitterCompletionJob.drain

      SendSubmitterInvitationEmailJob.jobs.map { |job| job['args'].first['submitter_id'] }
    end

    it 'emails the third party, who can then sign' do
      expect(run_completion_chain).to eq([third_signer.id])
      expect(open_form(third_signer)).to include('<submission-form')

      submit_form(third_signer)

      expect(response).to have_http_status(:ok)
      expect(third_signer.reload.completed_at).to be_present
    end

    context 'when the template preserves the signer order' do
      before { enforce_order_on_template }

      it 'emails the third party, who waits for the second' do
        expect(run_completion_chain).to eq([third_signer.id])
        expect(open_form(third_signer)).to include(awaiting_message)

        submit_form(third_signer)

        expect(response).to have_http_status(:unprocessable_content)
        expect(third_signer.reload.completed_at).to be_nil
      end
    end

    context 'when the account enforces the signing order' do
      before { enforce_order_on_account }

      it 'emails the third party, who waits for the second' do
        expect(run_completion_chain).to eq([third_signer.id])
        expect(open_form(third_signer)).to include(awaiting_message)

        submit_form(third_signer)

        expect(response).to have_http_status(:unprocessable_content)
        expect(third_signer.reload.completed_at).to be_nil
      end
    end
  end

  context 'when the submission does not preserve the signer order' do
    let(:submitters_order) { 'random' }

    it 'lets a later party submit first' do
      submit_form(second_signer)

      expect(response).to have_http_status(:ok)
      expect(second_signer.reload.completed_at).to be_present
    end

    it 'lets a later party decline first' do
      decline_form(second_signer)

      expect(response).to redirect_to(submit_form_path(slug: second_signer.slug))
      expect(second_signer.reload.declined_at).to be_present
    end

    it 'shows a later party the form' do
      expect(open_form(second_signer)).to include('<submission-form')
    end

    context 'when the account enforces the signing order' do
      before { enforce_order_on_account }

      it 'holds a later party on the awaiting page and refuses the submit' do
        expect(open_form(second_signer)).to include(awaiting_message)

        submit_form(second_signer)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq('error' => awaiting_message)
        expect(second_signer.reload.completed_at).to be_nil
      end
    end
  end

  context 'with a single signer' do
    let(:submitter_count) { 1 }

    it 'lets the signer submit' do
      enforce_order_on_template
      submit_form(first_signer)

      expect(response).to have_http_status(:ok)
      expect(first_signer.reload.completed_at).to be_present
    end
  end
end
