# frozen_string_literal: true

RSpec.describe 'Signing consent' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, only_field_types: %w[text]) }
  let(:submission) { create(:submission, template:) }
  let(:submitter) { create(:submitter, submission:, uuid: template.submitters.first['uuid'], account:) }

  before do
    create(:account_config, account:, key: AccountConfig::SIGNING_CONSENT_KEY,
                            value: { 'version' => 'v1', 'text' => "Electronic records.\nDecline to withdraw." })
  end

  it 'shows the disclosure before the first field and completes only after the signer ticks and accepts' do
    visit submit_form_path(slug: submitter.slug)

    expect(page).to have_content('Electronic records and signature disclosure')
    expect(page).to have_css('#consent_text', text: 'Decline to withdraw.')
    expect(page).to have_no_field('First Name')

    click_button 'Continue'

    expect(page).to have_css('#consent_form')
    expect(page).to have_no_field('First Name')

    check 'I agree to use electronic records and signatures'
    click_button 'Continue'

    fill_in 'First Name', with: 'Mary'
    find('#submit_form_button').click

    expect(page).to have_content('Form has been completed!')

    event_types = submitter.submission_events.order(:event_timestamp).pluck(:event_type)

    expect(submitter.reload.completed_at).to be_present
    expect(event_types.count('accept_consent')).to eq(1)
    expect(event_types.index('accept_consent')).to be < event_types.index('complete_form')
  end

  it 'withdraws consent from the decline form' do
    visit submit_form_path(slug: submitter.slug)

    find('#decline_button').click
    fill_in 'reason', with: 'Paper, please'

    within('dialog[open]') do
      check 'Withdraw my consent to use electronic records and signatures'
      click_button 'Decline'
    end

    expect(page).to have_content('Form has been declined')
    expect(submitter.reload.declined_at).to be_present
    expect(submitter.submission_events.pluck(:event_type)).to include('decline_form', 'withdraw_consent')
  end
end
