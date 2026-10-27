# frozen_string_literal: true

require Rails.root.join('db/migrate/20261027160000_platform_users_stand_for_tenant')

RSpec.describe PlatformUsersStandForTenant do
  it 'sets up the users of platform accounts made before, and leaves other accounts alone' do
    platform = create(:account, name: 'Acme Robotics', external_id: 'org_1')
    made_before = create(:user, account: platform, first_name: nil, last_name: nil)
    made_before.user_configs.create!(key: UserConfig::RECEIVE_COMPLETED_EMAIL, value: true)
    other = create(:user, first_name: 'Jane', last_name: 'Doe')

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(made_before.reload).to have_attributes(first_name: 'Acme Robotics', last_name: nil)
    expect(made_before.user_configs.pluck(:key,
                                          :value)).to contain_exactly([UserConfig::RECEIVE_COMPLETED_EMAIL, false],
                                                                      [UserConfig::RECEIVE_DECLINED_EMAIL, false])
    expect(other.reload).to have_attributes(first_name: 'Jane', last_name: 'Doe')
    expect(other.user_configs).to be_empty

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(made_before.user_configs.count).to eq(2)
  end
end
