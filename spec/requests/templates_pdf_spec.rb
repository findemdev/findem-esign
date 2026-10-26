# frozen_string_literal: true

describe 'Templates PDF API' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': author.access_token.token } }
  let(:file) { Base64.strict_encode64(Rails.root.join('spec/fixtures/sample-document.pdf').binread) }
  let(:form_pdf) do
    pdf = HexaPDF::Document.new
    page = pdf.pages.add
    pdf.acro_form(create: true).create_text_field('Employee name').create_widget(page, Rect: [72, 700, 300, 720])
    io = StringIO.new
    pdf.write(io)
    io.string
  end

  before do
    allow(Accounts).to receive(:link_expires_at).and_return(Accounts::LINK_EXPIRES_AT)
  end

  describe 'POST /api/templates/pdf' do
    it 'creates a template with its signer roles and the fields the request places' do
      expect do
        post '/api/templates/pdf', headers:, params: {
          name: 'Offer letter',
          external_id: 'people:rcpt_1',
          roles: %w[Employee Manager],
          documents: [{
            name: 'offer-letter.pdf',
            file:,
            fields: [
              { name: 'Employee name', type: 'text', role: 'Employee',
                areas: [{ x: 0.1, y: 0.2, w: 0.3, h: 0.04, page: 1 }] },
              { name: 'Approved by', type: 'signature', role: 'manager', required: false,
                areas: [{ x: 0.5, y: 0.8, w: 0.3, h: 0.06, page: 1 }] },
              { name: 'Start date', type: 'date', readonly: true, default_value: '{{date}}',
                preferences: { format: 'MM/DD/YYYY' }, areas: [{ x: 0.1, y: 0.3, w: 0.2, h: 0.03, page: 1 }] },
              { name: 'Employee number', type: 'cells', required: false,
                areas: [{ x: 0.6, y: 0.2, w: 0.18, h: 0.03, page: 1, cell_w: 0.02 }] },
              { name: 'Relocating', type: 'radio', options: %w[Yes No],
                areas: [{ x: 0.1, y: 0.5, w: 0.02, h: 0.02, page: 1, option: 'Yes' },
                        { x: 0.2, y: 0.5, w: 0.02, h: 0.02, page: 1, option: 'No' }] }
            ]
          }]
        }.to_json
      end.to change(Template, :count).by(1)

      expect(response).to have_http_status(:ok)

      template = Template.last
      employee, manager = template.submitters
      document = template.documents.first

      expect(template).to have_attributes(name: 'Offer letter', external_id: 'people:rcpt_1', source: 'api',
                                          account_id: account.id, author_id: author.id)
      expect(template.submitters.pluck('name')).to eq(%w[Employee Manager])
      expect(template.schema).to eq([{ 'attachment_uuid' => document.uuid, 'name' => 'offer-letter' }])

      name, approval, start, number, relocating = template.fields

      expect(name).to include('name' => 'Employee name', 'type' => 'text', 'required' => true,
                              'submitter_uuid' => employee['uuid'],
                              'areas' => [{ 'x' => 0.1, 'y' => 0.2, 'w' => 0.3, 'h' => 0.04, 'page' => 0,
                                            'attachment_uuid' => document.uuid }])
      expect(approval).to include('type' => 'signature', 'required' => false, 'submitter_uuid' => manager['uuid'])
      expect(start).to include('readonly' => true, 'default_value' => '{{date}}', 'submitter_uuid' => employee['uuid'],
                               'preferences' => { 'format' => 'MM/DD/YYYY' })
      expect(number).to include('type' => 'cells', 'required' => false)
      expect(number['areas'].first['cell_w']).to eq(0.02)
      expect(relocating['options'].pluck('value')).to eq(%w[Yes No])
      expect(relocating['areas'].pluck('option_uuid')).to eq(relocating['options'].pluck('uuid'))
      expect(response.parsed_body).to include('id' => template.id, 'name' => 'Offer letter', 'source' => 'api',
                                              'external_id' => 'people:rcpt_1')
      expect(response.parsed_body['submitters'].pluck('name')).to eq(%w[Employee Manager])
      expect(response.parsed_body['documents'].pluck('uuid')).to eq([document.uuid])
    end

    it "takes the PDF's own form fields for the first role when the request places none" do
      post '/api/templates/pdf', headers:, params: {
        name: 'Fillable form', roles: %w[Employee], documents: [{ file: Base64.strict_encode64(form_pdf) }]
      }.to_json

      expect(response).to have_http_status(:ok)

      template = Template.last

      expect(template.fields.size).to eq(1)
      expect(template.fields.first).to include('name' => 'Employee name', 'type' => 'text',
                                               'submitter_uuid' => template.submitters.first['uuid'])
      expect(template.fields.first['areas'].first['attachment_uuid']).to eq(template.documents.first.uuid)
    end

    it 'finds fields on the pages only when asked' do
      allow(Templates::DetectFields).to receive(:call) do |_io, attachment:|
        [[{ uuid: SecureRandom.uuid, type: 'signature', required: true, preferences: {},
            areas: [{ x: 0.1, y: 0.8, w: 0.3, h: 0.05, page: 0, attachment_uuid: attachment.uuid }] }], nil]
      end

      post '/api/templates/pdf', headers:, params: { name: 'Plain letter', documents: [{ file: }] }.to_json

      expect(response).to have_http_status(:ok)
      expect(Template.last.fields).to eq([])
      expect(Template.last.submitters.pluck('name')).to eq(['First Party'])
      expect(Templates::DetectFields).not_to have_received(:call)

      post '/api/templates/pdf', headers:, params: { name: 'Plain letter', detect_fields: true,
                                                     documents: [{ file: }] }.to_json

      expect(response).to have_http_status(:ok)

      template = Template.last

      expect(template.fields.size).to eq(1)
      expect(template.fields.first).to include('type' => 'signature',
                                               'submitter_uuid' => template.submitters.first['uuid'])
      expect(template.fields.first['areas'].first['attachment_uuid']).to eq(template.documents.first.uuid)
    end

    it 'refuses a file that is not a PDF' do
      expect do
        post '/api/templates/pdf', headers:, params: {
          name: 'Not a PDF', documents: [{ file: Base64.strict_encode64('plain text') }]
        }.to_json
      end.not_to change(Template, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => 'documents[0].file must be a base64-encoded PDF')
    end

    it 'refuses a field for a role the template does not have, keeping nothing' do
      expect do
        post '/api/templates/pdf', headers:, params: {
          name: 'Offer letter', roles: %w[Employee],
          documents: [{ file:, fields: [{ name: 'Approved by', type: 'signature', role: 'Manager',
                                          areas: [{ x: 0.5, y: 0.8, w: 0.3, h: 0.06, page: 1 }] }] }]
        }.to_json
      end.not_to change(Template, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => "role Manager is not one of the template's roles")
    end

    it 'refuses an area off the page' do
      post '/api/templates/pdf', headers:, params: {
        name: 'Offer letter',
        documents: [{ file:, fields: [{ name: 'Name', areas: [{ x: 1.5, y: 0.2, w: 0.3, h: 0.04, page: 1 }] }] }]
      }.to_json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to start_with('x must be a number from 0 to 1')

      post '/api/templates/pdf', headers:, params: {
        name: 'Offer letter',
        documents: [{ file:, fields: [{ name: 'Name', areas: [{ x: 0.1, y: 0.2, w: 0.3, h: 0.04, page: 9 }] }] }]
      }.to_json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to start_with('page 9 is not in')
      expect(Template.count).to eq(0)
    end

    it 'needs an API token' do
      post '/api/templates/pdf', params: { name: 'Offer letter', documents: [{ file: }] }.to_json

      expect(response).to have_http_status(:unauthorized)
      expect(Template.count).to eq(0)
    end
  end
end
