# frozen_string_literal: true

require 'cancan/matchers'

describe Ability do
  let(:account) { create(:account, external_id: 'org_1') }
  let(:admin) { create(:user, account:) }
  let(:member) { create(:user, account:, role: User::MEMBER_ROLE) }
  let(:template) { create(:template, account:, author: admin) }

  it 'gives a member only the documents they sent, every template to send from, and only their own to change' do
    own = create(:submission, :with_submitters, template:, created_by_user: member)
    other = create(:submission, :with_submitters, template:, created_by_user: admin)
    own_template = create(:template, account:, author: member)
    other_account = create(:account)
    elsewhere = create(:template, account: other_account, author: create(:user, account: other_account))
    ability = described_class.new(member)

    expect(Submission.accessible_by(ability)).to contain_exactly(own)
    expect(Submitter.accessible_by(ability)).to match_array(own.submitters)
    expect(Template.accessible_by(ability)).to contain_exactly(template, own_template)
    expect(ability).to be_able_to(:manage, own)
    expect(ability).to be_able_to(:manage, own.submitters.first)
    expect(ability).not_to be_able_to(:read, other)
    expect(ability).not_to be_able_to(:read, other.submitters.first)
    expect(ability).to be_able_to(:create, Submission.new(account_id: account.id))
    expect(ability).to be_able_to(:read, template)
    expect(ability).not_to be_able_to(:update, template)
    expect(ability).to be_able_to(:update, own_template)
    expect(ability).not_to be_able_to(:destroy, own_template)
    expect(ability).not_to be_able_to(:destroy, template)
    expect(ability).to be_able_to(:update, TemplateFolder.new(account_id: account.id, author_id: member.id))
    expect(ability).not_to be_able_to(:destroy, TemplateFolder.new(account_id: account.id, author_id: member.id))
    expect(ability).not_to be_able_to(:read, elsewhere)
  end

  it 'keeps the account, its users, settings, webhooks and keys from a member' do
    ability = described_class.new(member)

    expect(ability).to be_able_to(:manage, member)
    expect(ability).not_to be_able_to(:read, admin)
    expect(ability).not_to be_able_to(:create, account.users.new)
    expect(ability).not_to be_able_to(:read, account)
    expect(ability).not_to be_able_to(:read, AccountConfig.new(account_id: account.id))
    expect(ability).not_to be_able_to(:read, EncryptedConfig.new(account_id: account.id))
    expect(ability).not_to be_able_to(:read, WebhookUrl.new(account_id: account.id))
    expect(ability).not_to be_able_to(:read, member.access_token)
    expect(ability).not_to be_able_to(:manage, McpToken.new(user: member))
    expect(ability).not_to be_able_to(:manage, :mcp)
  end

  it 'gives an administrator every document of the account' do
    sent = create(:submission, :with_submitters, template:, created_by_user: member)

    expect(described_class.new(admin)).to be_able_to(:manage, sent)
    expect(described_class.new(admin)).to be_able_to(:destroy, template)
  end

  it 'keeps what the platform’s apps send from everyone but the user that stands for the tenant, and not the templates' do
    tenant = create(:user, account:)
    tenant.user_configs.create!(key: UserConfig::STANDS_FOR_TENANT, value: true)
    app_template = create(:template, account:, author: tenant)
    from_app = create(:submission, :with_submitters, template: app_template, created_by_user: tenant)
    from_person = create(:submission, :with_submitters, template: app_template, created_by_user: admin)
    from_link = create(:submission, :with_submitters, template:, created_by_user: nil)
    ability = described_class.new(admin)

    expect(Submission.accessible_by(ability)).to contain_exactly(from_person, from_link)
    expect(Submitter.accessible_by(ability)).to match_array(from_person.submitters + from_link.submitters)
    expect(ability).not_to be_able_to(:read, from_app)
    expect(ability).not_to be_able_to(:read, from_app.submitters.first)
    expect(ability).to be_able_to(:manage, from_person)
    expect(ability).to be_able_to(:manage, from_link)
    expect(ability).to be_able_to(:create, Submission.new(account_id: account.id))
    expect(ability).to be_able_to(:update, app_template)
    expect(Submission.accessible_by(described_class.new(member))).to be_empty
    expect(Submission.accessible_by(described_class.new(tenant))).to contain_exactly(from_app, from_person, from_link)
  end

  it 'holds nothing back in an account no platform runs' do
    plain = create(:account)
    owner = create(:user, account: plain)
    keyed = create(:user, account: plain)
    keyed.user_configs.create!(key: UserConfig::STANDS_FOR_TENANT, value: true)
    sent = create(:submission, :with_submitters, template: create(:template, account: plain, author: keyed),
                                                 created_by_user: keyed)

    expect(described_class.new(owner)).to be_able_to(:manage, sent)
  end
end
