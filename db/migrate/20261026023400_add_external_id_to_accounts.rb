# frozen_string_literal: true

class AddExternalIdToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :external_id, :string
    add_index :accounts, :external_id, unique: true
  end
end
