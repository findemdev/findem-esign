# frozen_string_literal: true

describe 'Sign up' do
  let(:form_params) do
    {
      user: { first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com', password: 'password' },
      account: { name: 'Acme Robotics', timezone: 'America/Los_Angeles', locale: 'en-US' }
    }
  end

  context 'when sign-up is closed on a multi-tenant instance', :multitenant do
    before do
      stub_const('ENV', ENV.to_h.except('ALLOW_SIGNUP'))
    end

    it 'answers 404' do
      get '/sign_up'

      expect(response).to have_http_status(:not_found)

      expect { post '/sign_up', params: form_params }.not_to change(Account, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'keeps an unknown email on the sign-in page' do
      create(:user, email: 'somebody@example.com')

      post '/sign_in', params: { user: { email: 'nobody@example.com', password: 'password' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/invalid email or password/i)
    end
  end

  context 'when single-tenant' do
    it 'answers 404 even with ALLOW_SIGNUP' do
      stub_const('ENV', ENV.to_h.except('MULTITENANT').merge('ALLOW_SIGNUP' => 'true'))

      get '/sign_up'

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when sign-up is open', :multitenant do
    before do
      stub_const('ENV', ENV.to_h.merge('ALLOW_SIGNUP' => 'true'))
    end

    it 'shows the form' do
      get '/sign_up'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Company name').and include('Password')
    end

    it 'creates the account and signs the user in' do
      expect do
        post '/sign_up', params: form_params
      end.to change(Account, :count).by(1).and change(User, :count).by(1)

      expect(response).to redirect_to(root_path)

      user = User.find_by!(email: 'jane@example.com')

      expect(user).to have_attributes(first_name: 'Jane', last_name: 'Doe', role: User::ADMIN_ROLE)
      expect(user.account).to have_attributes(name: 'Acme Robotics', timezone: 'Pacific Time (US & Canada)',
                                              locale: 'en-US')
      expect(user.account.encrypted_configs.find_by(key: EncryptedConfig::ESIGN_CERTS_KEY)).to be_present
      expect(session['warden.user.user.key']).to be_present
    end

    it 'rejects an invalid form' do
      expect do
        post '/sign_up', params: form_params.deep_merge(user: { password: 'short' })
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('too short')

      expect do
        post '/sign_up', params: form_params.deep_merge(account: { name: '' })
      end.not_to change(Account, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
