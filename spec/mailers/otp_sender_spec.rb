# frozen_string_literal: true

describe 'One-time code email sender', type: :mailer do
  let(:account) { create(:account, external_id: "tenant-#{SecureRandom.hex(4)}") }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submitter) { create(:submission, :with_submitters, template:, created_by_user: author).submitters.first }

  let(:product_sender) { "#{Docuseal.product_name} <#{Docuseal::SUPPORT_EMAIL}>" }

  context 'when multi-tenant', :multitenant do
    it "sends a signer's code as the product" do
      mail = SubmitterMailer.otp_verification_email(submitter)

      expect(mail[:from].to_s).to eq(product_sender)
    end

    it "sends a shared link's code as the product" do
      mail = TemplateMailer.otp_verification_email(template, email: 'signer@example.com')

      expect(mail[:from].to_s).to eq(product_sender)
    end

    it 'keeps the product name when production mail sets only the address' do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.application.config.action_mailer).to receive(:delivery_method).and_return(:smtp)
      stub_const('ENV', ENV.to_h.merge('SMTP_FROM' => 'notifications@example.com'))

      message = SubmitterMailer.otp_verification_email(submitter).message

      ActionMailerConfigsInterceptor.delivering_email(message)

      expect(message[:from].to_s).to eq("#{Docuseal.product_name} <notifications@example.com>")
      expect(message.to_s).not_to include('DocuSeal')
    end

    it "keeps the author's address when the account sends codes from it" do
      create(:account_config, account:, key: 'custom_otp_email', value: true)

      mail = SubmitterMailer.otp_verification_email(submitter)

      expect(mail.from).to eq([author.email])
    end
  end
end
