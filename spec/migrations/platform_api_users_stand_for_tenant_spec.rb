# frozen_string_literal: true

require Rails.root.join('db/migrate/20261116180000_platform_api_users_stand_for_tenant')

RSpec.describe PlatformApiUsersStandForTenant do
  it 'marks the user a platform account’s apps send with, and no person' do
    platform = create(:account, external_id: 'org_1')
    tenant = create(:user, account: platform)
    tenant.access_token
    person = create(:user, account: platform, sign_in_count: 2)
    person.access_token
    unkeyed = create(:user, account: platform)
    elsewhere = create(:user)
    elsewhere.access_token

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    marked = UserConfig.where(key: UserConfig::STANDS_FOR_TENANT).pluck(:user_id, :value)

    expect(marked).to contain_exactly([tenant.id, true])
    expect(unkeyed.user_configs.where(key: UserConfig::STANDS_FOR_TENANT)).to be_empty
  end
end
