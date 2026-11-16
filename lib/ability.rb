# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    if user.role == User::MEMBER_ROLE
      member_rules(user)
    else
      admin_rules(user)
    end
  end

  private

  def admin_rules(user)
    can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
    end

    can :destroy, Template, account_id: user.account_id
    can :manage, TemplateFolder, account_id: user.account_id
    can :manage, TemplateSharing, template: { account_id: user.account_id }
    can :manage, Submission, account_id: user.account_id
    can :manage, Submitter, account_id: user.account_id
    can :manage, User, account_id: user.account_id
    can :manage, EncryptedConfig, account_id: user.account_id
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, AccountConfig, account_id: user.account_id
    can :manage, UserConfig, user_id: user.id
    can :manage, Account, id: user.account_id
    can :manage, AccessToken, user_id: user.id
    can :manage, McpToken, user_id: user.id
    can :manage, WebhookUrl, account_id: user.account_id

    can :manage, :mcp
  end

  # A member sees and manages only the documents they sent. They send from any template of the account and change only the
  # templates and folders they made, without archiving or deleting them: the documents other people sent from a template
  # go with it. The account's users, settings, webhooks and keys stay with its administrators.
  def member_rules(user)
    can :read, Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:)
    end

    can :create, Template, account_id: user.account_id
    can :update, Template, account_id: user.account_id, author_id: user.id
    can :read, TemplateFolder, account_id: user.account_id
    can %i[create update], TemplateFolder, account_id: user.account_id, author_id: user.id
    can :create, Submission, account_id: user.account_id
    can :manage, Submission, account_id: user.account_id, created_by_user_id: user.id
    can :manage, Submitter, account_id: user.account_id, submission: { created_by_user_id: user.id }
    can :manage, User, id: user.id
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, UserConfig, user_id: user.id
  end
end
