# frozen_string_literal: true

module Params
  class TemplateCreateValidator < BaseValidator
    FIELD_TYPES = %w[text signature initials date number image checkbox multiple file radio select stamp phone
                     cells].freeze

    def call
      required(params, :name)
      type(params, :name, String)
      type(params, :external_id, String)
      type(params, :folder_name, String)
      type(params, :roles, Array)
      roles(params[:roles])
      boolean(params, :detect_fields)
      required(params, :documents)
      type(params, :documents, Array)

      in_path_each(params, %i[documents]) do |document|
        required(document, :file)
        type(document, :file, String)
        type(document, :name, String)
        type(document, :fields, Array)

        in_path_each(document, %i[fields]) { |field| field(field) }
      end
    end

    private

    def roles(roles)
      return if roles.blank?
      return if roles.all? { |role| role.is_a?(String) && role.strip.present? } &&
                roles.map { |role| role.strip.downcase }.uniq.size == roles.size

      raise_error('roles must be distinct names')
    end

    def field(field)
      type(field, :name, String)
      value_in(field, :type, FIELD_TYPES) if field[:type].present?
      type(field, :role, String)
      type(field, :options, Array)
      type(field, :preferences, Hash)
      boolean(field, :required)
      boolean(field, :readonly)
      required(field, :areas)
      type(field, :areas, Array)

      in_path_each(field, %i[areas]) { |area| area(area) }
    end

    def area(area)
      %i[x y w h cell_w].each do |key|
        next if (key == :cell_w && area[key].nil?) || fraction?(area[key])

        raise_error("#{key} must be a number from 0 to 1")
      end

      raise_error('w and h must be more than 0') unless area[:w].to_f.positive? && area[:h].to_f.positive?
      raise_error('page must be a whole number from 1') unless area[:page].is_a?(Integer) && area[:page] >= 1
    end

    def fraction?(value)
      value.is_a?(Numeric) && value.between?(0, 1)
    end
  end
end
