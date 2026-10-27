# frozen_string_literal: true

# Users of platform accounts made before the platform API set them up to stand for their tenant: named after the account,
# no completed or declined notices. The same settings, applied once.
class PlatformUsersStandForTenant < ActiveRecord::Migration[8.1]
  class MigrationAccount < ApplicationRecord
    self.table_name = 'accounts'
  end

  class MigrationUser < ApplicationRecord
    self.table_name = 'users'
  end

  class MigrationUserConfig < ApplicationRecord
    self.table_name = 'user_configs'
  end

  QUIET_KEYS = %w[receive_completed_email receive_declined_email].freeze

  def up
    MigrationAccount.where.not(external_id: nil).find_each do |account|
      MigrationUser.where(account_id: account.id).find_each do |user|
        unless user.first_name == account.name && user.last_name.blank?
          user.update_columns(first_name: account.name, last_name: nil)
        end

        QUIET_KEYS.each do |key|
          MigrationUserConfig.find_or_initialize_by(user_id: user.id, key:).update!(value: false.to_json)
        end
      end
    end
  end

  def down; end
end
