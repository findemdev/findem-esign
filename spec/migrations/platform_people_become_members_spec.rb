# frozen_string_literal: true

require Rails.root.join('db/migrate/20261116080000_platform_people_become_members')

RSpec.describe PlatformPeopleBecomeMembers do
  it 'makes the people of platform accounts members, and leaves the user that stands for a tenant alone' do
    platform = create(:account, name: 'Acme Robotics', external_id: 'org_1')
    tenant = create(:user, account: platform, first_name: 'Acme Robotics', last_name: nil)
    person = create(:user, account: platform, sign_in_count: 3)
    elsewhere = create(:user, sign_in_count: 2)

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(person.reload.role).to eq(User::MEMBER_ROLE)
    expect(tenant.reload.role).to eq(User::ADMIN_ROLE)
    expect(elsewhere.reload.role).to eq(User::ADMIN_ROLE)
  end
end
