# frozen_string_literal: true

# What a member of a platform account opens: the documents they sent and every template to send from; never another
# person's document, the account's settings or its other users. They change their own templates without archiving them,
# a template of theirs copies them nobody else's documents, and their email stays the one the platform signs them in with.
describe 'Platform members' do
  let(:account) { create(:account, external_id: 'org_1') }
  let(:admin) { create(:user, account:) }
  let(:member) { create(:user, account:, role: User::MEMBER_ROLE) }
  let(:template) { create(:template, account:, author: admin, name: 'Offer letter') }
  let(:own_template) { create(:template, account:, author: member, name: 'Team handbook') }
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

  it 'lets a member send from and edit their own template, but not archive it' do
    sign_in(member)

    get "/templates/#{own_template.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-with-send-button="true"')

    delete "/templates/#{own_template.id}"

    expect(response).to redirect_to('/')
    expect(own_template.reload.archived_at).to be_nil
  end

  it 'copies a member no documents through their template, and keeps their own signing among their documents' do
    own_template.update!(preferences: { 'bcc_completed' => member.email })
    template.update!(preferences: { 'bcc_completed' => admin.email })

    expect(own_template.bcc_completed).to be_nil
    expect(template.bcc_completed).to eq(admin.email)

    sign_in(admin)

    get "/templates/#{own_template.id}/submissions/new"

    expect(response.body).not_to include('type="hidden" name="bcc_completed[]"')

    get "/templates/#{template.id}/submissions/new"

    expect(response.body).to include(%(type="hidden" name="bcc_completed[]" value="#{admin.email}"))

    sign_in(member)

    expect { patch "/start_form_self/#{template.id}" }.to change(Submission, :count).by(1)

    expect(Submission.order(:id).last.created_by_user).to eq(member)
  end

  it 'keeps a member to the email the platform signs them in with' do
    sign_in(member)

    patch '/settings/profile/update_contact', params: { user: { email: 'someone.else@northwind.test' } }

    expect(member.reload.email).not_to eq('someone.else@northwind.test')
  end

  it 'opens every document for an administrator from the platform' do
    sign_in(admin)

    get '/submissions'

    expect(response.body).to include('Ada Sent-By-Member', 'Grace Sent-By-Admin')
  end
end
