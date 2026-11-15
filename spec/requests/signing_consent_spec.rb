# frozen_string_literal: true

describe 'Signing consent' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, only_field_types: %w[text]) }
  let(:submission) { create(:submission, template:, created_by_user: author) }
  let(:submitter) do
    create(:submitter, submission:, uuid: template.submitters.first['uuid'], account:, name: 'Mary Signer')
  end
  let(:field_uuid) { template.fields.first['uuid'] }
  let(:text) { "Consent to electronic records.\nWithdraw it by declining." }
  let(:sha256) { Digest::SHA256.hexdigest(text) }

  def configure_consent(version: 'v1', consent_text: text)
    AccountConfig.find_or_initialize_by(account:, key: AccountConfig::SIGNING_CONSENT_KEY)
                 .update!(value: { 'version' => version, 'text' => consent_text })
  end

  def accept_consent(version: 'v1', digest: sha256)
    post submit_form_consent_index_path(submitter.slug), params: { version:, sha256: digest }
  end

  def complete_form
    put submit_form_path(slug: submitter.slug), params: { completed: 'true', values: { field_uuid => 'Mary' } }
  end

  def decline(**params)
    post submit_form_decline_index_path(submitter.slug), params: { reason: 'Paper, please', **params }
  end

  def event_types
    submitter.submission_events.order(:event_timestamp).pluck(:event_type)
  end

  def audit_log_text
    create(:encrypted_config, account:, key: EncryptedConfig::ESIGN_CERTS_KEY,
                              value: GenerateCertificate.call.transform_values(&:to_pem))

    data = Submissions::GenerateAuditTrail.call(submission.reload).download

    Pdfium::Document.open_bytes(data) do |doc|
      Array.new(doc.page_count) { |i| doc.get_page(i).text }.join("\n")
    end.squish
  end

  def signing_page
    get submit_form_path(slug: submitter.slug)

    expect(response).to have_http_status(:ok)

    Nokogiri::HTML(response.body)
  end

  context 'when the account has no disclosure' do
    it 'shows no disclosure and completes as before' do
      html = signing_page

      expect(html.at('submission-form')['data-consent']).to eq('')
      expect(html.at('#withdraw_consent')).to be_nil

      complete_form

      expect(response).to have_http_status(:ok)
      expect(submitter.reload.completed_at).to be_present
      expect(event_types).to eq(%w[start_form complete_form])
    end

    it 'ignores a withdrawal on decline' do
      expect(Submitters::SerializeForWebhook.call(submitter)['consent_withdrawn']).to be_nil

      decline(withdraw_consent: '1')

      expect(submitter.reload.declined_at).to be_present
      expect(event_types).to eq(%w[decline_form])
      expect(Submitters::SerializeForWebhook.call(submitter)['consent_withdrawn']).to be(false)
    end

    it 'refuses an acceptance' do
      accept_consent

      expect(response).to have_http_status(:unprocessable_content)
      expect(SubmissionEvent.count).to eq(0)
    end
  end

  context 'when the account has a disclosure' do
    before { configure_consent }

    it 'shows it on the signing page until the signer accepts it, and offers the withdrawal' do
      html = signing_page

      expect(JSON.parse(html.at('submission-form')['data-consent']))
        .to eq('version' => 'v1', 'text' => text, 'sha256' => sha256)
      expect(html.at('#withdraw_consent')['name']).to eq('withdraw_consent')
      expect(html.at('form[action$="/decline"] details').text).to include('Withdraw it by declining.')

      accept_consent
      html = signing_page

      expect(html.at('submission-form')['data-consent']).to eq('')
      expect(html.at('#withdraw_consent')).to be_present
    end

    it 'refuses completion until the signer accepts, then records the acceptance once' do
      complete_form

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error'])
        .to eq(I18n.t('consent_required_refresh_the_page_and_accept_the_disclosure'))
      expect(submitter.reload.completed_at).to be_nil
      expect(submitter.values).to eq({})
      expect(event_types).to eq([])

      accept_consent

      expect(response).to have_http_status(:ok)

      event = submitter.submission_events.sole

      expect(event.event_type).to eq('accept_consent')
      expect(event.data.slice('version', 'sha256', 'text')).to eq('version' => 'v1', 'sha256' => sha256, 'text' => text)
      expect(event.data['ip']).to be_present

      accept_consent

      expect(response).to have_http_status(:ok)
      expect(event_types).to eq(%w[accept_consent])

      complete_form

      expect(response).to have_http_status(:ok)
      expect(submitter.reload.completed_at).to be_present
      expect(event_types).to eq(%w[accept_consent start_form complete_form])
    end

    it 'refuses an acceptance of another version or text, and records nothing' do
      [{ version: 'v0' }, { digest: Digest::SHA256.hexdigest('Other text') }, { version: nil, digest: nil }]
        .each do |args|
          accept_consent(**args)

          expect(response).to have_http_status(:unprocessable_content), args.inspect
          expect(response.parsed_body['error']).to eq(I18n.t('the_disclosure_has_changed_refresh_the_page'))
        end

      expect(SubmissionEvent.count).to eq(0)
    end

    it 'asks again when the text or the version changes' do
      accept_consent
      configure_consent(consent_text: "#{text} Updated.")
      complete_form

      expect(response).to have_http_status(:unprocessable_content)

      accept_consent(digest: Digest::SHA256.hexdigest("#{text} Updated."))
      configure_consent(version: 'v2', consent_text: "#{text} Updated.")
      complete_form

      expect(response).to have_http_status(:unprocessable_content)
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'does not count an acceptance made before the link was delegated' do
      travel_to(2.minutes.ago) { accept_consent }
      create(:submission_event, submission:, submitter:, event_type: 'delegate_form', event_timestamp: 1.minute.ago,
                                data: { 'email' => 'delegate@example.com' })

      complete_form

      expect(response).to have_http_status(:unprocessable_content)

      accept_consent

      expect(event_types).to eq(%w[accept_consent delegate_form accept_consent])

      complete_form

      expect(response).to have_http_status(:ok)
      expect(submitter.reload.completed_at).to be_present
    end

    it 'refuses an acceptance from a signer who has declined or completed' do
      submitter.update!(declined_at: Time.current)
      accept_consent

      expect(response).to have_http_status(:unprocessable_content)

      submitter.update!(declined_at: nil, completed_at: Time.current)
      accept_consent

      expect(response).to have_http_status(:unprocessable_content)
      expect(SubmissionEvent.count).to eq(0)
    end

    it 'lists the acceptance with its version and sha256, and the accepted text, on the audit log' do
      accept_consent
      complete_form

      audit = audit_log_text

      expect(audit).to include('Electronic records consent accepted by Mary Signer')
      expect(audit).to include('Disclosure version v1')
      expect(audit.index('Electronic records consent accepted')).to be < audit.index('Submission completed by')
      expect(audit).to include('Electronic records and signature disclosure Disclosure version v1 ' \
                               "Disclosure SHA-256 #{sha256} #{text.squish}")
    end

    it 'leaves a recorded text that does not match its sha256 off the audit log' do
      accept_consent
      complete_form

      event = submitter.submission_events.find_by!(event_type: 'accept_consent')
      event.update!(data: event.data.merge('text' => 'Edited afterwards.'))

      audit = audit_log_text

      expect(audit).to include('Disclosure version v1')
      expect(audit).not_to include('Electronic records and signature disclosure')
      expect(audit).not_to include('Edited afterwards.')
    end

    context 'when the platform then changes and removes the disclosure' do
      let(:headers) { { 'Authorization' => 'Bearer platform-token-123', 'Content-Type' => 'application/json' } }

      before do
        stub_const('ENV', ENV.to_h.except('ATS_PLATFORM_CONFIG_FILE')
                                .merge('PLATFORM_API_TOKEN' => 'platform-token-123'))
        account.update!(external_id: 'consent-tenant-2')
      end

      def provision_consent(consent)
        post('/api/platform/accounts', headers:, params: { external_id: account.external_id, name: account.name,
                                                           email: 'platform@tenant.example.com', consent: }.to_json)

        expect(response).to have_http_status(:ok)
      end

      it 'keeps the accepted text and its sha256 on the acceptance and the audit log' do
        accept_consent
        provision_consent({ version: 'v2', text: 'A replacement disclosure.' })

        expect(Submitters.signing_consent(account)).to include('version' => 'v2', 'text' => 'A replacement disclosure.')

        provision_consent(nil)

        expect(Submitters.signing_consent(account)).to be_nil

        complete_form

        expect(response).to have_http_status(:ok)

        data = submitter.submission_events.find_by!(event_type: 'accept_consent').data

        expect(data.slice('version', 'sha256', 'text')).to eq('version' => 'v1', 'sha256' => sha256, 'text' => text)
        expect(Digest::SHA256.hexdigest(data['text'])).to eq(data['sha256'])

        audit = audit_log_text

        expect(audit).to include("Disclosure version v1 Disclosure SHA-256 #{sha256} #{text.squish}")
        expect(audit).not_to include('replacement')
      end
    end

    it 'records a withdrawal on decline and carries it on the webhook payload' do
      decline(withdraw_consent: '1')

      expect(response).to redirect_to(submit_form_path(submitter.slug))
      expect(submitter.reload.declined_at).to be_present
      expect(event_types).to eq(%w[decline_form withdraw_consent])
      expect(submitter.submission_events.find_by!(event_type: 'withdraw_consent').data)
        .to include('version' => 'v1', 'sha256' => sha256, 'text' => text)
      expect(Submitters::SerializeForWebhook.call(submitter).slice('decline_reason', 'consent_withdrawn'))
        .to eq('decline_reason' => 'Paper, please', 'consent_withdrawn' => true)
    end

    it 'records no withdrawal when the box is left unticked' do
      decline

      expect(event_types).to eq(%w[decline_form])
      expect(Submitters::SerializeForWebhook.call(submitter.reload)['consent_withdrawn']).to be(false)
    end

    context 'when the signer invites the next party' do
      let(:template) { create(:template, account:, author:, submitter_count: 2, only_field_types: %w[text]) }
      let(:next_uuid) { template.submitters.second['uuid'] }
      let(:submission) do
        create(:submission, template:, created_by_user: author).tap do |s|
          s.update!(template_submitters: s.template_submitters.map do |ts|
            ts['uuid'] == next_uuid ? ts.merge('invite_by_uuid' => template.submitters.first['uuid']) : ts
          end)
        end
      end

      def invite
        post submit_form_invite_index_path(submitter.slug),
             params: { submission: { submitters: [{ uuid: next_uuid, email: 'next.party@example.com' }] } }
      end

      it 'refuses the invite, which completes the form, until the signer accepts' do
        submitter.update!(values: { field_uuid => 'Mary' })

        expect { invite }.not_to change(Submitter, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(submitter.reload.completed_at).to be_nil

        accept_consent

        expect { invite }.to change(Submitter, :count).by(1)
        expect(response).to have_http_status(:ok)
        expect(submitter.reload.completed_at).to be_present
      end
    end
  end

  describe 'POST /api/platform/accounts' do
    let(:headers) { { 'Authorization' => 'Bearer platform-token-123', 'Content-Type' => 'application/json' } }
    let(:body) { { external_id: 'consent-tenant-1', name: 'Acme Robotics', email: 'platform@tenant.example.com' } }

    before do
      stub_const('ENV', ENV.to_h.except('ATS_PLATFORM_CONFIG_FILE').merge('PLATFORM_API_TOKEN' => 'platform-token-123'))
    end

    def provision(**extra)
      post('/api/platform/accounts', params: body.merge(extra).to_json, headers:)
    end

    def stored_consent
      Account.find_by!(external_id: body[:external_id])
             .account_configs.where(key: AccountConfig::SIGNING_CONSENT_KEY).pluck(:value)
    end

    it 'sets, keeps, replaces and removes the account disclosure' do
      provision(consent: { version: 'v1', text: })

      expect(response).to have_http_status(:created)
      expect(stored_consent).to eq([{ 'version' => 'v1', 'text' => text }])

      provision

      expect(response).to have_http_status(:ok)
      expect(stored_consent).to eq([{ 'version' => 'v1', 'text' => text }])

      provision(consent: { version: 'findem-ersd/2.0', text: 'Second text', extra: 'dropped' })

      expect(stored_consent).to eq([{ 'version' => 'findem-ersd/2.0', 'text' => 'Second text' }])

      provision(consent: nil)

      expect(response).to have_http_status(:ok)
      expect(stored_consent).to eq([])

      provision(consent: { version: 'v3', text: })
      provision(consent: {})

      expect(stored_consent).to eq([])
    end

    it 'answers 422 on an invalid disclosure and creates nothing' do
      invalid = {
        { text: } => /version is required/,
        { version: 'v1' } => /text is required/,
        { version: 'v1', text: " \n " } => /text is required/,
        { version: 'v 1', text: } => /version is invalid/,
        { version: "v1\n", text: } => /version is invalid/,
        { version: 'v' * 101, text: } => /version is invalid/,
        { version: 1, text: } => /version must be a String/,
        { version: 'v1', text: %w[a] } => /text must be a String/,
        'nope' => /consent must be a Object/
      }

      invalid.each do |consent, error|
        provision(consent:)

        expect(response).to have_http_status(:unprocessable_content), consent.inspect
        expect(response.parsed_body['error']).to match(error)
      end

      expect(Account.count).to eq(0)
    end
  end
end
