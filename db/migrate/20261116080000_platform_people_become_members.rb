# frozen_string_literal: true

# Before roles, everyone the platform signed in became an administrator of their tenant's account. Each of those people is
# now a member until their next sign-in through the platform, which gives its owners and admins the account again
# (PlatformSessions). The user that stands for a tenant is only ever used by API key and never signs in on a browser, so
# it keeps its role.
class PlatformPeopleBecomeMembers < ActiveRecord::Migration[8.1]
  class MigrationAccount < ApplicationRecord
    self.table_name = 'accounts'
  end

  class MigrationUser < ApplicationRecord
    self.table_name = 'users'
  end

  def up
    MigrationUser.where(account_id: MigrationAccount.where.not(external_id: nil).select(:id))
                 .where.not(sign_in_count: 0)
                 .update_all(role: 'member')
  end

  def down; end
end
