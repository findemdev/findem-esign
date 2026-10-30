# frozen_string_literal: true

describe 'Email attribution footer', type: :mailer do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submitter) { create(:submission, :with_submitters, template:, created_by_user: author).submitters.first }

  let(:mail) { SubmitterMailer.invitation_email(submitter) }
  let(:html) { Nokogiri::HTML((mail.html_part || mail).body.decoded) }
  let(:footer) { html.css('p').find { |p| p.text.include?('Sent using') } }

  shared_examples 'an open-source footer' do
    it 'links the product URL and drops the free document signing line' do
      expect(footer.css('a').pluck('href')).to eq([Docuseal::PRODUCT_EMAIL_URL])
      expect(footer.text.squish).to eq("Sent using #{Docuseal.product_name} open-source software.")
      expect(html.css('a').pluck('href').grep(%r{/(?:start|open)(?:[/?#]|\z)})).to be_empty
      expect(html.text).not_to include('free document signing')
    end
  end

  context 'when multi-tenant', :multitenant do
    let(:account) { create(:account, external_id: "tenant-#{SecureRandom.hex(4)}") }

    it_behaves_like 'an open-source footer'
  end

  context 'when single-tenant' do
    before { allow(Docuseal).to receive(:multitenant?).and_return(false) }

    it_behaves_like 'an open-source footer'
  end

  context 'with a testing account', :multitenant do
    let(:account) { create(:account, :with_testing_account).testing_accounts.first }

    it 'keeps the testing-mode line' do
      expect(account).to be_testing
      expect(footer.css('a').pluck('href')).to eq([Docuseal::PRODUCT_EMAIL_URL])
      expect(footer.text.squish).to eq("Sent using #{Docuseal.product_name} in testing mode")
      expect(html.text).not_to include('free document signing')
    end
  end
end
