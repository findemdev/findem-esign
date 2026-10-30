# frozen_string_literal: true

# Optional platform entry for unauthenticated browser visits. Local sign-in remains available.
module PlatformEntry
  module_function

  def url_for(path)
    return if Docuseal.platform_api_token.blank? || ENV['FINDEM_SIGN_ENTRY_URL'].blank?

    uri = URI.parse(ENV.fetch('FINDEM_SIGN_ENTRY_URL'))
    local_http = uri.scheme == 'http' && %w[localhost 127.0.0.1 [::1]].include?(uri.host)

    return unless uri.host.present? && (uri.scheme == 'https' || local_http)
    return if uri.userinfo || uri.fragment

    query = URI.decode_www_form(uri.query.to_s).reject { |pair| pair.first == 'next' }
    uri.query = URI.encode_www_form(query + [['next', PlatformSessions.next_path(path)]])
    uri.to_s
  rescue URI::InvalidURIError, ArgumentError
    nil
  end
end
