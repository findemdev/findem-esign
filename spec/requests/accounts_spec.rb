# frozen_string_literal: true

describe 'Deleting an account', :multitenant do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }

  before do
    sign_in(user)
  end

  it 'archives the account and the user, and releases the email' do
    email = user.email

    delete '/settings/account', headers: { 'Accept' => 'text/vnd.turbo-stream.html, text/html' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Your account will be permanently deleted within 2 months.')
    expect(account.reload.archived_at).to be_present
    expect(user.reload).to have_attributes(email: email.sub('@', '+removed@'))
    expect(user.archived_at).to be_present
    expect(user.locked_at).to be_present
  end
end
