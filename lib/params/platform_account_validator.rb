# frozen_string_literal: true

module Params
  class PlatformAccountValidator < BaseValidator
    EXTERNAL_ID_REGEXP = /\A[\w.:-]{1,255}\z/
    URL_REGEXP = %r{\Ahttps?://\S+\z}i
    HEADER_NAME_REGEXP = /\A[\w-]+\z/

    def call
      required(params, :external_id)
      format(params, :external_id, EXTERNAL_ID_REGEXP, message: 'external_id is invalid')
      required(params, :name)
      type(params, :name, String)
      required(params, :email)
      email_format(params, :email)
      value_in(params, :locale, I18n.available_locales.map(&:to_s)) if params[:locale].present?
      timezone(params, :timezone)
      type(params, :webhook, Hash)

      in_path(params, [:webhook]) do |webhook|
        required(webhook, :url)
        format(webhook, :url, URL_REGEXP, message: 'url must be an http(s) URL')
        type(webhook, :secret, Hash)
        type(webhook, :events, Array)
        secret_headers(webhook)
        events(webhook)
      end
    end

    private

    def timezone(params, key)
      return if params[key].blank?

      TZInfo::Timezone.get(ActiveSupport::TimeZone::MAPPING[params[key]] || params[key])
    rescue TZInfo::InvalidTimezoneIdentifier
      raise_error("#{key} is invalid")
    end

    def secret_headers(webhook)
      webhook[:secret]&.each_pair do |name, value|
        next if HEADER_NAME_REGEXP.match?(name) && value.is_a?(String)

        raise_error("secret header '#{name}' is invalid")
      end
    end

    def events(webhook)
      Array.wrap(webhook[:events]).each do |event|
        next if WebhookUrl::EVENTS.include?(event)

        raise_error("events must be one of #{WebhookUrl::EVENTS.join(', ')}")
      end
    end
  end
end
