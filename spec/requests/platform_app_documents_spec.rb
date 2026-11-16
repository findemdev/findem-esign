# frozen_string_literal: true

# What the platform's apps send through an account (People's offers and forms, volume hiring's offers) is theirs to show:
# nobody signed in to the account sees those documents, their signers or their files, administrators included, while the
# apps keep them through the account's API key and everyone keeps the templates.
describe 'Documents the platform’s apps send' do
  let(:account) { create(:account, external_id: 'org_1') }
  let(:tenant) { create(:user, account:, first_name: 'Acme Robotics', last_name: nil) }
  let(:admin) { create(:user, account:) }
  let(:template) { create(:template, account:, author: tenant, name: 'Offer letter') }
  let!(:from_app) { create(:submission, :with_submitters, template:, created_by_user: tenant) }
  let!(:from_admin) { create(:submission, :with_submitters, template:, created_by_user: admin) }

  before do
    Accounts.create_initial_configs(account)
    tenant.user_configs.create!(key: UserConfig::STANDS_FOR_TENANT, value: true)
    from_app.submitters.first.update!(name: 'Ada Sent-By-App', email: 'ada.app@northwind.test')
    from_admin.submitters.first.update!(name: 'Grace Sent-By-Admin')
  end

  it 'leaves them out of an administrator’s lists, pages and signer search, and keeps the template theirs to change' do
    sign_in(admin)

    get '/submissions'

    expect(response.body).to include('Grace Sent-By-Admin')
    expect(response.body).not_to include('Ada Sent-By-App')

    get "/templates/#{template.id}"

    expect(response.body).to include('Grace Sent-By-Admin')
    expect(response.body).not_to include('Ada Sent-By-App')

    get "/submissions/#{from_app.id}"

    expect(response).to redirect_to('/')

    get '/submitters_autocomplete', params: { field: 'email', q: 'ada.app' }

    expect(response.body).not_to include('ada.app@northwind.test')

    get "/templates/#{template.id}/edit"

    expect(response).to have_http_status(:ok)
  end

  it 'keeps them for the apps, through the account’s API key' do
    get '/api/submissions', headers: { 'X-Auth-Token' => tenant.access_token.token }

    expect(response.parsed_body['data'].pluck('id')).to contain_exactly(from_app.id, from_admin.id)
  end
end
