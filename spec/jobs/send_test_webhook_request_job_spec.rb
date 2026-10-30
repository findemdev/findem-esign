# frozen_string_literal: true

RSpec.describe SendTestWebhookRequestJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }
  let(:submission) { create(:submission, template:, created_by_user: user) }
  let(:submitter) do
    create(:submitter, submission:, uuid: template.submitters.first['uuid'], completed_at: Time.current)
  end
  let(:webhook_url) { create(:webhook_url, account:, url: 'https://hooks.example.com/sign') }

  before do
    stub_request(:post, webhook_url.url).to_return(status: 200)
  end

  it 'sends the test event with the product user agent' do
    described_class.new.perform('submitter_id' => submitter.id, 'webhook_url_id' => webhook_url.id)

    expect(WebMock).to have_requested(:post, webhook_url.url).with(
      body: hash_including('event_type' => 'form.completed'),
      headers: { 'Content-Type' => 'application/json', 'User-Agent' => 'Findem Sign Webhook' }
    ).once
  end
end
