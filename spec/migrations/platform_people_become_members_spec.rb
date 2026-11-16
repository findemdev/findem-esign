# frozen_string_literal: true

require Rails.root.join('db/migrate/20261116080000_platform_people_become_members')

RSpec.describe PlatformPeopleBecomeMembers do
  it 'makes the people of platform accounts members without keys or remembered sign-ins, and leaves the rest alone' do
    platform = create(:account, name: 'Acme Robotics', external_id: 'org_1')
    tenant = create(:user, account: platform, first_name: 'Acme Robotics', last_name: nil)
    tenant_token = tenant.access_token.token
    person = create(:user, account: platform, sign_in_count: 3, remember_created_at: 1.day.ago)
    person.access_token
    person.mcp_tokens.create!(name: 'Assistant')
    elsewhere = create(:user, sign_in_count: 2, remember_created_at: 1.day.ago)
    elsewhere.access_token

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(person.reload).to have_attributes(role: User::MEMBER_ROLE, remember_created_at: nil)
    expect(AccessToken.where(user: person)).to be_empty
    expect(McpToken.where(user: person)).to be_empty
    expect(tenant.reload).to have_attributes(role: User::ADMIN_ROLE)
    expect(AccessToken.find_by(user: tenant).token).to eq(tenant_token)
    expect(elsewhere.reload).to have_attributes(role: User::ADMIN_ROLE)
    expect(elsewhere.remember_created_at).to be_present
    expect(AccessToken.where(user: elsewhere)).to exist
  end
end
