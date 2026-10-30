# frozen_string_literal: true

describe 'Account deletion', :multitenant do
  let(:user) { create(:user, account:) }

  before do
    sign_in(user)
  end

  context 'when the platform manages the account' do
    let(:account) { create(:account, name: 'Northwind', external_id: '68fa0b2c1d2e3f4a5b6c7d8e') }

    it 'hides the Danger Zone' do
      get '/settings/account'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Delete my account', 'account_delete_button')
    end

    it 'refuses a DELETE and archives nothing' do
      email = user.email

      delete '/settings/account'

      expect(response).to redirect_to('/')
      expect(account.reload.archived_at).to be_nil
      expect(user.reload).to have_attributes(archived_at: nil, locked_at: nil, email:)
    end

    it 'refuses a DELETE from its testing environment' do
      testing_account = Account.create!(name: 'Testing - Northwind',
                                        linked_account_account: AccountLinkedAccount.new(account:))
      create(:user, account: testing_account)

      post '/testing_account'
      get '/settings/account'

      expect(response.body).to include('value="Testing - Northwind"')

      delete '/settings/account'

      expect(response).to redirect_to('/')
      expect(account.reload.archived_at).to be_nil
      expect(testing_account.reload.archived_at).to be_nil
      expect(user.reload).to have_attributes(archived_at: nil, locked_at: nil)
    end
  end

  context 'when the account has no external_id' do
    let(:account) { create(:account) }

    it 'still shows the Danger Zone' do
      get '/settings/account'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Delete my account', 'account_delete_button')
    end
  end
end
