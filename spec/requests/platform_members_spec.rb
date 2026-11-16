# frozen_string_literal: true

# What a member of a platform account opens: the documents they sent and every template to send from; never another
# person's document, the account's settings, its other users or an API key. An administrator from the platform opens
# every document, and gets no API key either.
describe 'Platform members' do
  let(:account) { create(:account, external_id: 'org_1') }
  let(:admin) { create(:user, account:) }
  let(:member) { create(:user, account:, role: User::MEMBER_ROLE) }
  let(:template) { create(:template, account:, author: admin, name: 'Offer letter') }
  let!(:own) { create(:submission, :with_submitters, template:, created_by_user: member) }
  let!(:other) { create(:submission, :with_submitters, template:, created_by_user: admin) }

  before do
    Accounts.create_initial_configs(account)
    own.submitters.first.update!(name: 'Ada Sent-By-Member')
    other.submitters.first.update!(name: 'Grace Sent-By-Admin')
  end

  it 'lists and opens only the documents a member sent, from any template of the account' do
    sign_in(member)

    get '/submissions'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Ada Sent-By-Member')
    expect(response.body).not_to include('Grace Sent-By-Admin')

    get "/submissions/#{own.id}"

    expect(response).to have_http_status(:ok)

    get "/submissions/#{other.id}"

    expect(response).to redirect_to('/')

    get '/'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Offer letter')
  end

  it 'keeps the account, its settings, webhooks and keys from a member, who sees only themself among the users' do
    sign_in(member)

    %w[/settings/account /settings/webhooks /settings/api].each do |path|
      get path

      expect(response).to redirect_to('/'), path
    end

    get '/settings/users'

    expect(response.body).to include(member.email)
    expect(response.body).not_to include(admin.email)
  end

  it 'opens every document for an administrator from the platform, with no API key' do
    sign_in(admin)

    get '/submissions'

    expect(response.body).to include('Ada Sent-By-Member', 'Grace Sent-By-Admin')

    get '/settings/api'

    expect(response).to redirect_to('/')
  end
end
