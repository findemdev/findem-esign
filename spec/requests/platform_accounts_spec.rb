# frozen_string_literal: true

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
    stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => platform_token))
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
  end
end
