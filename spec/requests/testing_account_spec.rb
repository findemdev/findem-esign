# frozen_string_literal: true

describe 'Testing environment', :multitenant do
  let(:external_id) { '68fa0b2c1d2e3f4a5b6c7d8e' }
  let(:account) { create(:account, name: 'Northwind', external_id:) }
  let(:user) { create(:user, account:) }

  before do
    sign_in(user)
  end

  it 'opens for a platform account and keeps external_id on the platform account only' do
    post '/testing_account'

    testing_account = account.testing_accounts.sole

    expect(response).to redirect_to(root_path)
    expect(testing_account).to have_attributes(name: 'Testing - Northwind', external_id: nil)
    expect(session[:impersonated_user_id]).to eq(testing_account.users.sole.uuid)
    expect(Account.find_by(external_id:)).to eq(account)
  end

  it 'reuses the testing account on the next switch' do
    post '/testing_account'
    delete '/testing_account'
    post '/testing_account'

    expect(response).to redirect_to(root_path)
    expect(account.testing_accounts.count).to eq(1)
  end
end
