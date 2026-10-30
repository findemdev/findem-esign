# frozen_string_literal: true

require 'tmpdir'

describe 'Platform accounts API' do
  let(:platform_token) { 'platform-token-123' }
  let(:headers) { { 'Authorization' => "Bearer #{platform_token}", 'Content-Type' => 'application/json' } }
  let(:external_id) { '68fa0b2c1d2e3f4a5b6c7d8e' }
  let(:webhook_params) do
    {
      url: "https://people.example.com/hr/webhooks/docuseal/#{external_id}",
      secret: { 'X-Findem-Webhook' => 'whsec-one' },
      events: %w[form.completed form.declined submission.expired]
    }
  end
  let(:body) do
    {
      external_id:,
      name: 'Acme Robotics',
      email: "people+#{external_id}@findem.ai",
      timezone: 'America/Los_Angeles',
      locale: 'en-US',
      webhook: webhook_params
    }
  end

  before do
    stub_const('ENV', ENV.to_h.except('ATS_PLATFORM_CONFIG_FILE').merge('PLATFORM_API_TOKEN' => platform_token))
  end

  describe 'POST /api/platform/accounts' do
    it 'does not exist without PLATFORM_API_TOKEN' do
      stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))

      expect do
        post('/api/platform/accounts', params: body.to_json, headers:)
      end.not_to change(Account, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects a wrong or missing token' do
      post '/api/platform/accounts', params: body.to_json, headers: headers.merge('Authorization' => 'Bearer nope')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'Not authenticated')

      post '/api/platform/accounts', params: body.to_json, headers: headers.except('Authorization')

      expect(response).to have_http_status(:unauthorized)
      expect(Account.count).to eq(0)
    end

    it 'creates the account, its admin user, an API token and the webhook' do
      expect do
        post('/api/platform/accounts', params: body.to_json, headers:)
      end.to change(Account, :count).by(1).and change(User, :count).by(1).and change(WebhookUrl, :count).by(1)

      expect(response).to have_http_status(:created)

      account = Account.find_by!(external_id:)
      user = account.users.first
      api_token = response.parsed_body['api_token']

      expect(response.parsed_body).to eq('account_id' => account.id, 'user_id' => user.id, 'api_token' => api_token)
      expect(api_token).to eq(user.access_token.token)
      expect(account).to have_attributes(name: 'Acme Robotics', timezone: 'Pacific Time (US & Canada)',
                                         locale: 'en-US')
      expect(user).to have_attributes(email: body[:email], role: User::ADMIN_ROLE, first_name: 'Acme Robotics',
                                      last_name: nil)
      expect(user.confirmed_at).to be_present
      expect(user.user_configs.pluck(:key, :value)).to contain_exactly([UserConfig::RECEIVE_COMPLETED_EMAIL, false],
                                                                       [UserConfig::RECEIVE_DECLINED_EMAIL, false])
      expect(account.encrypted_configs.find_by(key: EncryptedConfig::ESIGN_CERTS_KEY).value).to be_present
      expect(account.webhook_urls.first).to have_attributes(url: webhook_params[:url],
                                                            secret: webhook_params[:secret],
                                                            events: webhook_params[:events])
      expect(ActionMailer::Base.deliveries).to be_empty

      get '/api/templates', headers: { 'x-auth-token' => api_token }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to eq([])
    end

    it 'creates the account without a webhook' do
      post('/api/platform/accounts', params: body.except(:webhook, :timezone, :locale).to_json, headers:)

      expect(response).to have_http_status(:created)
      expect(Account.find_by!(external_id:)).to have_attributes(timezone: 'UTC', locale: 'en-US')
      expect(WebhookUrl.count).to eq(0)
    end

    it 'repeats for the same external_id with a new token and the webhook upserted' do
      post('/api/platform/accounts', params: body.to_json, headers:)

      first = response.parsed_body
      old_token = first['api_token']
      changed_webhook = webhook_params.merge(secret: { 'X-Findem-Webhook' => 'whsec-two' }, events: %w[form.completed])

      expect do
        post('/api/platform/accounts', params: body.merge(webhook: changed_webhook).to_json, headers:)
      end.not_to(change { [Account.count, User.count, WebhookUrl.count] })

      expect(response).to have_http_status(:ok)

      second = response.parsed_body

      expect(second.slice('account_id', 'user_id')).to eq(first.slice('account_id', 'user_id'))
      expect(second['api_token']).not_to eq(old_token)

      account = Account.find(first['account_id'])

      expect(account.webhook_urls.first).to have_attributes(url: webhook_params[:url],
                                                            secret: { 'X-Findem-Webhook' => 'whsec-two' },
                                                            events: %w[form.completed])

      get '/api/templates', headers: { 'x-auth-token' => old_token }

      expect(response).to have_http_status(:unauthorized)

      get '/api/templates', headers: { 'x-auth-token' => second['api_token'] }

      expect(response).to have_http_status(:ok)
    end

    it 'keeps the user standing for the tenant on a repeat' do
      post('/api/platform/accounts', params: body.to_json, headers:)

      user = User.find(response.parsed_body['user_id'])
      user.update!(first_name: 'Someone', last_name: 'Else')
      user.user_configs.find_by!(key: UserConfig::RECEIVE_COMPLETED_EMAIL).update!(value: true)

      post('/api/platform/accounts', params: body.to_json, headers:)

      expect(user.reload).to have_attributes(first_name: 'Acme Robotics', last_name: nil)
      expect(user.user_configs.pluck(:key, :value)).to contain_exactly([UserConfig::RECEIVE_COMPLETED_EMAIL, false],
                                                                       [UserConfig::RECEIVE_DECLINED_EMAIL, false])
    end

    it 'sends its user no password-reset email' do
      post('/api/platform/accounts', params: body.to_json, headers:)

      post user_password_path, params: { user: { email: body[:email] } }

      expect(ActionMailer::Base.deliveries).to be_empty

      person = create(:user)

      post user_password_path, params: { user: { email: person.email } }

      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[person.email]])
    end

    it 'answers 422 on invalid input' do
      invalid = {
        body.except(:external_id) => 'external_id is required',
        body.merge(external_id: 'no spaces allowed') => 'external_id is invalid',
        body.except(:name) => 'name is required',
        body.merge(email: 'nope') => /email must follow the email format/,
        body.merge(locale: 'xx-XX') => /locale must be one of/,
        body.merge(timezone: 'Mars/Olympus') => 'timezone is invalid',
        body.merge(webhook: webhook_params.except(:url)) => /url is required/,
        body.merge(webhook: webhook_params.merge(url: 'ftp://example.com')) => /url must be an http/,
        body.merge(webhook: webhook_params.merge(events: %w[nope])) => /events must be one of/,
        body.merge(webhook: webhook_params.merge(secret: { 'Bad Header' => 'x' })) => /secret header 'Bad Header'/,
        body.merge(webhook: 'nope') => /webhook must be a Object/
      }

      invalid.each do |params, error|
        post('/api/platform/accounts', params: params.to_json, headers:)

        expect(response).to have_http_status(:unprocessable_content), params.inspect
        expect(response.parsed_body['error']).to match(error)
      end

      post('/api/platform/accounts', params: '{not json', headers:)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Account.count).to eq(0)
    end

    it 'answers 422 when the email belongs to another account and creates nothing' do
      create(:user, email: body[:email])

      expect do
        post('/api/platform/accounts', params: body.to_json, headers:)
      end.not_to change(Account, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq('Email has already been taken')
    end

    context 'with a separately scoped ATS credential' do
      let(:ats_token) { 'synthetic-ats-platform-token' }
      let(:ats_headers) { headers.merge('Authorization' => "Bearer #{ats_token}") }
      let(:ats_body) { body.merge(external_id: "findem-ats:#{external_id}", email: "ats+#{external_id}@findem.ai") }
      let(:directory) { Dir.mktmpdir('ats-platform-request-') }
      let(:config_path) { File.join(directory, 'config.json') }

      before do
        File.write(config_path, { platform_token: ats_token }.to_json)
        File.chmod(0o400, config_path)
        stub_const('ENV', ENV.to_h.merge('ATS_PLATFORM_CONFIG_FILE' => config_path))
      end

      after { FileUtils.remove_entry(directory) }

      it 'creates and rekeys an ATS account while preserving the same account, user and webhook' do
        post('/api/platform/accounts', params: ats_body.to_json, headers: ats_headers)

        expect(response).to have_http_status(:created)

        first = response.parsed_body
        changed_webhook = webhook_params.merge(secret: { 'X-Findem-Webhook' => 'ats-replacement-secret' })

        expect do
          post('/api/platform/accounts', params: ats_body.merge(webhook: changed_webhook).to_json, headers: ats_headers)
        end.not_to(change { [Account.count, User.count, WebhookUrl.count] })

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.slice('account_id', 'user_id')).to eq(first.slice('account_id', 'user_id'))
        expect(response.parsed_body['api_token']).not_to eq(first['api_token'])
        expect(Account.find(first['account_id']).webhook_urls.first.secret).to eq(changed_webhook[:secret])
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it 'keeps the existing global token able to provision People accounts' do
        post('/api/platform/accounts', params: body.to_json, headers:)

        expect(response).to have_http_status(:created)
        expect(Account.find(response.parsed_body['account_id']).external_id).to eq(external_id)
      end

      it 'works with only the scoped credential configured and rejects missing or wrong credentials' do
        stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))

        attempts = [ats_headers.except('Authorization'), headers, headers.merge('Authorization' => 'Bearer wrong')]

        attempts.each do |invalid_headers|
          post('/api/platform/accounts', params: ats_body.to_json, headers: invalid_headers)

          expect(response).to have_http_status(:unauthorized)
          expect(Account.count).to eq(0)
        end

        post('/api/platform/accounts', params: ats_body.to_json, headers: ats_headers)

        expect(response).to have_http_status(:created)
      end

      it 'rejects every non-ATS or empty namespace before creating any records' do
        [external_id, 'findem-ats:', 'Findem-ats:org', 'findem-atsx:org', 'prefix-findem-ats:org'].each do |outside|
          expect do
            post('/api/platform/accounts', params: ats_body.merge(external_id: outside).to_json, headers: ats_headers)
          end.not_to(change { [Account.count, User.count, WebhookUrl.count, AccessToken.count] })

          expect(response).to have_http_status(:forbidden)
          expect(response.parsed_body).to eq('error' => 'Not authorized')
        end
      end

      it 'bounds the namespace suffix at the existing external ID maximum' do
        post('/api/platform/accounts',
             params: ats_body.merge(external_id: "findem-ats:#{'x' * 245}").to_json,
             headers: ats_headers)

        expect(response).to have_http_status(:unprocessable_content)
        expect(Account.count).to eq(0)

        post('/api/platform/accounts',
             params: ats_body.merge(external_id: "findem-ats:#{'x' * 244}").to_json,
             headers: ats_headers)

        expect(response).to have_http_status(:created)
      end

      it 'cannot rekey or change a People account by supplying its external ID, email or numeric refs' do
        post('/api/platform/accounts', params: body.to_json, headers:)

        people = response.parsed_body
        account = Account.find(people['account_id'])
        user = User.find(people['user_id'])
        before = [account.attributes, user.attributes, account.webhook_urls.first.attributes]
        attempted = body.merge(name: 'Replaced', account_id: account.id, user_id: user.id,
                               webhook: webhook_params.merge(secret: { 'X-Findem-Webhook' => 'replaced' }))

        post('/api/platform/accounts', params: attempted.to_json, headers: ats_headers)

        expect(response).to have_http_status(:forbidden)
        expect([account.reload.attributes, user.reload.attributes, account.webhook_urls.first.reload.attributes])
          .to eq(before)
        expect(user.access_token.reload.token).to eq(people['api_token'])
        expect(Account.count).to eq(1)
        expect(User.count).to eq(1)
      end

      it 'rolls back a scoped create when a normalized email belongs to another account' do
        post('/api/platform/accounts', params: body.to_json, headers:)

        people = response.parsed_body
        user = User.find(people['user_id'])
        before = [user.account.attributes, user.attributes, user.account.webhook_urls.first.attributes]
        attempted = ats_body.merge(email: " #{body[:email].upcase} ", account_id: people['account_id'],
                                   user_id: user.id)

        expect do
          post('/api/platform/accounts', params: attempted.to_json, headers: ats_headers)
        end.not_to(change { [Account.count, User.count, WebhookUrl.count, AccessToken.count] })

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to eq('Email has already been taken')
        expect(
          [user.account.reload.attributes, user.reload.attributes, user.account.webhook_urls.first.reload.attributes]
        ).to eq(before)
        expect(user.access_token.reload.token).to eq(people['api_token'])
        expect(Account.find_by(external_id: ats_body[:external_id])).to be_nil
      end

      it 'ignores foreign numeric refs when the scoped external ID and email are new' do
        person = create(:user)
        prior_token = person.access_token.token

        post('/api/platform/accounts',
             params: ats_body.merge(account_id: person.account_id, user_id: person.id).to_json,
             headers: ats_headers)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['account_id']).not_to eq(person.account_id)
        expect(response.parsed_body['user_id']).not_to eq(person.id)
        expect(person.access_token.reload.token).to eq(prior_token)
      end

      it 'fails closed for equal scoped and global tokens without falling back to global scope' do
        stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => ats_token))

        [body, ats_body].each do |params|
          post('/api/platform/accounts', params: params.to_json, headers: ats_headers)

          expect(response).to have_http_status(:service_unavailable)
          expect(response.parsed_body).to eq('error' => 'Platform configuration is unavailable')
          expect(Account.count).to eq(0)
        end
      end

      it 'does not fall back to the global token with an explicitly missing or malformed file' do
        [File.join(directory, 'missing.json'), config_path].each do |path|
          File.chmod(0o600, config_path)
          File.write(config_path, '{private-invalid-config')
          File.chmod(0o400, config_path)
          stub_const('ENV', ENV.to_h.merge('ATS_PLATFORM_CONFIG_FILE' => path))

          post('/api/platform/accounts', params: body.to_json, headers:)

          expect(response).to have_http_status(:service_unavailable)
          expect(response.parsed_body).to eq('error' => 'Platform configuration is unavailable')
          expect(Account.count).to eq(0)
        end
      end

      it 'does not grant the scoped platform token access to ordinary tenant APIs' do
        get '/api/templates', headers: { 'X-Auth-Token' => ats_token }

        expect(response).to have_http_status(:unauthorized)
        expect(Account.count).to eq(0)
      end
    end
  end
end
