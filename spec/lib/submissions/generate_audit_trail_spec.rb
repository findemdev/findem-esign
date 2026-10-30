# frozen_string_literal: true

RSpec.describe Submissions::GenerateAuditTrail do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }
  let(:submission) { create(:submission, template:, created_by_user: user) }

  before do
    create(:encrypted_config, account:, key: EncryptedConfig::ESIGN_CERTS_KEY,
                              value: GenerateCertificate.call.transform_values(&:to_pem))

    submitter = create(:submitter, submission:, uuid: template.submitters.first['uuid'], completed_at: Time.current)

    create(:submission_event, submission:, submitter:, event_type: 'complete_form')
  end

  it 'brands the header with the product name and links it to the product site' do
    data = described_class.call(submission).download

    text = Pdfium::Document.open_bytes(data) do |doc|
      Array.new(doc.page_count) { |i| doc.get_page(i).text }.join("\n")
    end

    pdf = HexaPDF::Document.new(io: StringIO.new(data))

    links = pdf.pages.flat_map do |page|
      page.each_annotation.select { |annot| annot[:Subtype] == :Link }.map { |annot| annot[:A][:URI] }
    end

    expect(text).to include(Docuseal.product_name)
    expect(text).not_to include('DocuSeal')
    expect(links).to include(Docuseal::PRODUCT_EMAIL_URL)
    expect(pdf.signatures.pluck(:Reason)).to eq(["Signed with #{Docuseal.product_name}"])
  end

  describe 'Verify link' do
    let(:links) do
      pdf = HexaPDF::Document.new(io: StringIO.new(described_class.call(submission).download))

      pdf.pages.flat_map do |page|
        page.each_annotation.select { |annot| annot[:Subtype] == :Link }.map { |annot| annot[:A][:URI] }
      end
    end

    it 'links e-signature settings on a single-tenant instance' do
      expect(links.grep(%r{/settings/esign\z})).to be_present
    end

    context 'when multi-tenant', :multitenant do
      it 'leaves out the link, which needs an account signers do not have' do
        expect(links.grep(%r{/settings/esign})).to be_empty
        expect(links).to include(Docuseal::PRODUCT_EMAIL_URL)
      end
    end
  end
end
