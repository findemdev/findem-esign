# frozen_string_literal: true

describe 'First-run setup' do
  let(:form_params) do
    {
      user: { first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com', password: 'password' },
      account: { name: 'Acme Robotics', timezone: 'UTC' },
      encrypted_config: { value: 'https://sign.example.com' }
    }
  end

  context 'when multi-tenant', :multitenant do
    it 'answers 404' do
      get '/setup'

      expect(response).to have_http_status(:not_found)

      expect { post '/setup', params: form_params }.not_to change(User, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'never sends a visitor of an empty instance there' do
      get '/'

      expect(response).to redirect_to(Docuseal::PRODUCT_URL)

      get '/settings'

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  context 'when single-tenant' do
    it 'sends a visitor of an empty instance to the setup' do
      get '/'

      expect(response).to redirect_to(setup_index_path)
    end

    it 'creates the first account' do
      expect { post '/setup', params: form_params }.to change(User, :count).by(1)

      expect(response).to redirect_to(newsletter_path)
    end
  end
end
