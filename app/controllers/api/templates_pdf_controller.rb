# frozen_string_literal: true

module Api
  # A template from PDFs sent as base64, in the shape of DocuSeal's POST /api/templates/pdf. `roles` names the signers in
  # order (one "First Party" when absent). Each document's fields come from the request (areas are fractions of the page
  # from its top-left corner, `page` counts from 1), else from the PDF's own form fields, else, with `detect_fields`, from
  # the fields found on its pages. A field without a role, and every field the PDF or the detection gives, is the first
  # role's.
  class TemplatesPdfController < ApiBaseController
    PDF_PREFIX = '%PDF-'
    PREFERENCES = %i[format align valign font font_size font_type color mask].freeze

    def create
      authorize!(:create, Template)

      Params::TemplateCreateValidator.call(params)

      template = new_template

      ApplicationRecord.transaction do
        template.save!

        attached = Array.wrap(params[:documents]).each_with_index.map do |document, index|
          attach(template, document, index)
        end

        schema = attached.map { |doc, _, _| { 'attachment_uuid' => doc.uuid, 'name' => doc.filename.base } }

        template.update!(schema:,
                         fields: attached.flat_map { |doc, data, document| fields_for(template, doc, data, document) })
      end

      WebhookUrls.enqueue_events(template, 'template.created')
      SearchEntries.enqueue_reindex(template)

      render json: Templates::SerializeForApi.call(template)
    rescue Templates::CreateAttachments::PdfEncrypted
      render json: { error: 'The PDF is password protected' }, status: :unprocessable_content
    end

    private

    def new_template
      roles = Array.wrap(params[:roles]).presence || [Template::DEFAULT_SUBMITTER_NAME]

      template = Template.new(account: current_account, author: current_user, name: params[:name],
                              external_id: params[:external_id].presence, source: :api,
                              folder: TemplateFolders.find_or_create_by_name(current_user, params[:folder_name]),
                              submitters: roles.map { |name| { 'name' => name, 'uuid' => SecureRandom.uuid } })

      Templates.maybe_assign_access(template)

      template
    end

    def attach(template, document, index)
      data = decode_pdf(document[:file], index)
      filename = "#{File.basename((document[:name].presence || template.name).to_s.tr('/', '-'), '.pdf')}.pdf"
      file = ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new(data), filename:,
                                                    type: Templates::CreateAttachments::PDF_CONTENT_TYPE)

      doc = Templates::CreateAttachments.handle_pdf_or_image(template, file, data, {},
                                                             extract_fields: document[:fields].blank?)

      [doc, data, document]
    end

    def decode_pdf(value, index)
      data = Base64.strict_decode64(value.to_s.gsub(/\s+/, ''))

      return data if data.byteslice(0, 1024).include?(PDF_PREFIX)

      raise ArgumentError
    rescue ArgumentError
      raise Params::BaseValidator::InvalidParameterError, "documents[#{index}].file must be a base64-encoded PDF"
    end

    def fields_for(template, doc, data, document)
      return placed_fields(template, doc, document[:fields]) if document[:fields].present?

      fields = Templates::ProcessDocument.normalize_attachment_fields(template, [doc])

      return fields if fields.present? || !params[:detect_fields].in?([true, 'true'])

      detected_fields(template, doc, data)
    end

    def placed_fields(template, doc, fields)
      pages = doc.metadata.dig('pdf', 'number_of_pages').to_i

      fields.map do |field|
        options = Array.wrap(field[:options]).map { |value| { 'uuid' => SecureRandom.uuid, 'value' => value.to_s } }

        {
          'uuid' => SecureRandom.uuid,
          'submitter_uuid' => submitter_for(template, field[:role])['uuid'],
          'name' => field[:name].to_s,
          'type' => field[:type].presence || 'text',
          'required' => field.key?(:required) ? field[:required] == true : true,
          'readonly' => field[:readonly] == true || nil,
          'default_value' => field[:default_value].presence,
          'preferences' => field[:preferences].present? ? field[:preferences].permit(*PREFERENCES).to_h : {},
          'options' => options.presence,
          'areas' => Array.wrap(field[:areas]).map { |area| area_for(area, doc, options, pages) }
        }.compact
      end
    end

    def area_for(area, doc, options, pages)
      page = area[:page].to_i

      if pages.positive? && page > pages
        raise Params::BaseValidator::InvalidParameterError, "page #{page} is not in #{doc.filename} (#{pages} pages)"
      end

      { 'x' => area[:x].to_f, 'y' => area[:y].to_f, 'w' => area[:w].to_f, 'h' => area[:h].to_f, 'page' => page - 1,
        'attachment_uuid' => doc.uuid, 'option_uuid' => option_uuid_for(area, options),
        'cell_w' => area[:cell_w]&.to_f }.compact
    end

    def option_uuid_for(area, options)
      return if area[:option].blank?

      options.find { |option| option['value'] == area[:option].to_s }&.dig('uuid') ||
        raise(Params::BaseValidator::InvalidParameterError, "option #{area[:option]} is not one of the field's options")
    end

    def submitter_for(template, role)
      return template.submitters.first if role.blank?

      template.submitters.find { |submitter| submitter['name'].casecmp?(role.to_s) } ||
        raise(Params::BaseValidator::InvalidParameterError, "role #{role} is not one of the template's roles")
    end

    def detected_fields(template, doc, data)
      fields, = Templates::DetectFields.call(StringIO.new(data), attachment: doc)

      fields.map do |field|
        field.deep_stringify_keys.merge('name' => '', 'submitter_uuid' => template.submitters.first['uuid'])
      end
    rescue StandardError => e
      Rollbar.error(e) if defined?(Rollbar)

      []
    end
  end
end
