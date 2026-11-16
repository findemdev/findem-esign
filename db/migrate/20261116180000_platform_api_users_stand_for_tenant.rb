# frozen_string_literal: true

# Marks the user each platform account's apps send with, as Api::Platform::AccountsController#stand_for_tenant does from
# now on: the one the platform API keyed, which holds the account's API key and has never signed in on a browser. What it
# sends is the apps' to show, so nobody signed in to the account sees it (Ability).
class PlatformApiUsersStandForTenant < ActiveRecord::Migration[8.1]
  class MigrationAccount < ApplicationRecord
    self.table_name = 'accounts'
  end

  class MigrationUser < ApplicationRecord
    self.table_name = 'users'
  end

  class MigrationAccessToken < ApplicationRecord
    self.table_name = 'access_tokens'
  end

  class MigrationUserConfig < ApplicationRecord
    self.table_name = 'user_configs'
  end

  def up
    MigrationUser.where(account_id: MigrationAccount.where.not(external_id: nil).select(:id), sign_in_count: 0)
                 .where(id: MigrationAccessToken.select(:user_id))
                 .pluck(:id).each do |user_id|
      MigrationUserConfig.find_or_initialize_by(user_id:, key: 'stands_for_tenant').update!(value: true.to_json)
    end
  end

  def down; end
end
