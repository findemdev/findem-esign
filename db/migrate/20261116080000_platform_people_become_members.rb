# frozen_string_literal: true

# Before roles, everyone the platform signed in became an administrator of their tenant's account. Each of those people is
# now a member until their next sign-in through the platform, which gives its owners and admins the account again
# (PlatformSessions); their API and MCP keys and their remembered sign-ins end here. The user that stands for a tenant is
# only ever used by API key and never signs in on a browser, so it keeps its role and its key.
class PlatformPeopleBecomeMembers < ActiveRecord::Migration[8.1]
  class MigrationAccount < ApplicationRecord
    self.table_name = 'accounts'
  end

  class MigrationUser < ApplicationRecord
    self.table_name = 'users'
  end

  class MigrationAccessToken < ApplicationRecord
    self.table_name = 'access_tokens'
  end

  class MigrationMcpToken < ApplicationRecord
    self.table_name = 'mcp_tokens'
  end

  def up
    people = MigrationUser.where(account_id: MigrationAccount.where.not(external_id: nil).select(:id))
                          .where.not(sign_in_count: 0)

    MigrationAccessToken.where(user_id: people.select(:id)).delete_all
    MigrationMcpToken.where(user_id: people.select(:id)).delete_all
    people.update_all(role: 'member', remember_created_at: nil)
  end

  def down; end
end
