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
    senders = people_senders(user)

    can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
    end

    can :destroy, Template, account_id: user.account_id
    can :manage, TemplateFolder, account_id: user.account_id
    can :manage, TemplateSharing, template: { account_id: user.account_id }
    document_rules(user, senders)
    can :manage, User, account_id: user.account_id
    can :manage, EncryptedConfig, account_id: user.account_id
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, AccountConfig, account_id: user.account_id
    can :manage, UserConfig, user_id: user.id
    can :manage, Account, id: user.account_id
    can :manage, AccessToken, user_id: user.id
    can :manage, McpToken, user_id: user.id
    # Webhooks carry everything about every document, so where the platform's apps send, the platform keeps them.
    can :manage, WebhookUrl, account_id: user.account_id unless senders

    can :manage, :mcp
  end

  # Every document of the account, but in an account a platform runs, not the ones its apps send: they send as the user
  # that stands for the tenant (Api::Platform::AccountsController), and those documents, their signers and their files are
  # the apps' to show. Everyone else there gets the documents a person sent, or nobody did (a template's shared link); the
  # templates stay as they are. The user that stands for the tenant keeps them all.
  def document_rules(user, senders)
    if senders
      can :manage, Submission, account_id: user.account_id, created_by_user_id: senders
      can :manage, Submitter, account_id: user.account_id, submission: { created_by_user_id: senders }
    else
      can :manage, Submission, account_id: user.account_id
      can :manage, Submitter, account_id: user.account_id
    end
  end

  # The account's users other than the ones that stand for the tenant, and nil for no sender; nil when nothing is held back.
  def people_senders(user)
    return unless user.account&.external_id?

    users = User.where(account_id: user.account_id)
    tenant_ids = UserConfig.where(user_id: users.select(:id), key: UserConfig::STANDS_FOR_TENANT)
                           .filter_map { |config| config.user_id if config.value == true }

    return if tenant_ids.empty? || tenant_ids.include?(user.id)

    [nil, *users.where.not(id: tenant_ids).pluck(:id)]
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
