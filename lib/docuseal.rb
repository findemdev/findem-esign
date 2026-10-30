# frozen_string_literal: true

module Docuseal
  InvalidAtsPlatformConfiguration = Class.new(StandardError)
  # Findem Sign: this instance is Findem's e-signature service (a fork of DocuSeal, AGPL-3.0; source at SOURCE_URL).
  PRODUCT_URL = 'https://www.findem.ai'
  SOURCE_URL = 'https://github.com/findemdev/findem-esign'
  PRODUCT_EMAIL_URL = ENV.fetch('PRODUCT_EMAIL_URL', PRODUCT_URL)
  NEWSLETTER_URL = "#{PRODUCT_URL}/newsletters".freeze
  PRODUCT_NAME = 'Findem Sign'
  DEFAULT_APP_URL = ENV.fetch('APP_URL', 'http://localhost:3000')
  GITHUB_URL = SOURCE_URL
  DISCORD_URL = 'https://discord.gg/qygYCDGck9'
  TWITTER_URL = 'https://twitter.com/docusealco'
  TWITTER_HANDLE = '@docusealco'
  CHATGPT_URL = "#{PRODUCT_URL}/chat".freeze
  SUPPORT_EMAIL = 'support@findem.ai'
  # Where the sign-in page's "Sign in with Findem Studio" starts the platform's hand-off (PlatformSessions).
  PLATFORM_SIGN_IN_URL = ENV['FINDEM_SIGN_ENTRY_URL'].presence ||
                         ENV.fetch('PLATFORM_SIGN_IN_URL', 'https://studio.findem.ai/people/sign')
  HOST = ENV.fetch('HOST', 'localhost')
  AATL_CERT_NAME = 'docuseal_aatl'
  CONSOLE_URL = if Rails.env.development?
                  'http://console.localhost.io:3001'
                elsif ENV['MULTITENANT'] == 'true'
                  "https://console.#{HOST}"
                else
                  'https://console.docuseal.com'
                end
  CLOUD_URL = if Rails.env.development?
                'http://localhost:3000'
              else
                'https://docuseal.com'
              end
  CDN_URL = if Rails.env.development?
              'http://localhost:3000'
            elsif ENV['MULTITENANT'] == 'true'
              "https://cdn.#{HOST}"
            else
              'https://cdn.docuseal.com'
            end

  CERTS = JSON.parse(ENV.fetch('CERTS', '{}'))
  TIMESERVER_URL = ENV.fetch('TIMESERVER_URL', nil)
  VERSION_FILE_PATH = Rails.root.join('.version')
  VERSION_FILE2_PATH = Rails.public_path.join('version')

  DEFAULT_URL_OPTIONS = {
    host: HOST,
    protocol: ENV['FORCE_SSL'].present? ? 'https' : 'http'
  }.freeze

  module_function

  def version
    @version ||=
      if VERSION_FILE_PATH.exist?
        VERSION_FILE_PATH.read.strip
      elsif VERSION_FILE2_PATH.exist?
        VERSION_FILE2_PATH.each_line.first.to_s.strip
      end
  end

  def multitenant?
    ENV['MULTITENANT'] == 'true'
  end

  # Public sign-up on a multi-tenant instance; closed by default, tenants come from the platform API.
  def signup_allowed?
    multitenant? && ENV['ALLOW_SIGNUP'] == 'true'
  end

  # Unrestricted platform credential, retained for the existing People integration.
  def platform_api_token
    ENV['PLATFORM_API_TOKEN'].presence
  end

  # Separate ATS credential: never read the shared People secret or accept it as a fallback.
  def ats_platform_api_token
    path = ENV['ATS_PLATFORM_CONFIG_FILE'].presence

    return if path.nil?

    unless path.start_with?('/') && path.length <= 4096 && path.exclude?("\0")
      raise InvalidAtsPlatformConfiguration, 'ATS platform configuration is invalid'
    end

    File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
      stat = file.stat

      unless stat.file? && stat.uid == Process.euid && (stat.mode & 0o777) == 0o400
        raise InvalidAtsPlatformConfiguration, 'ATS platform configuration is invalid'
      end

      bytes = file.read(8193).to_s
      config = JSON.parse(bytes)
      token = config['platform_token'] if config.is_a?(Hash)

      unless bytes.bytesize <= 8192 && config.is_a?(Hash) && config.keys == ['platform_token'] &&
             token.is_a?(String) && token.match?(/\A[\x21-\x7e]{16,4096}\z/)
        raise InvalidAtsPlatformConfiguration, 'ATS platform configuration is invalid'
      end

      token
    end
  rescue SystemCallError, IOError, JSON::ParserError, ArgumentError
    raise InvalidAtsPlatformConfiguration, 'ATS platform configuration is invalid'
  end

  def advanced_formats?
    multitenant?
  end

  def demo?
    ENV['DEMO'] == 'true'
  end

  def active_storage_public?
    ENV['ACTIVE_STORAGE_PUBLIC'] == 'true'
  end

  def default_pkcs
    return if Docuseal::CERTS['enabled'] == false

    @default_pkcs ||= GenerateCertificate.load_pkcs(Docuseal::CERTS)
  end

  def fulltext_search?
    return @fulltext_search unless @fulltext_search.nil?

    @fulltext_search =
      if SearchEntry.table_exists?
        Docuseal.multitenant? || AccountConfig.exists?(key: :fulltext_search, value: true)
      else
        false
      end
  end

  def enable_pwa?
    true
  end

  def pdf_format
    @pdf_format ||= ENV['PDF_FORMAT'].to_s.downcase
  end

  def trusted_certs
    @trusted_certs ||=
      ENV['TRUSTED_CERTS'].to_s.gsub('\\n', "\n").split("\n\n").map do |base64|
        OpenSSL::X509::Certificate.new(base64)
      end
  end

  def default_url_options
    return DEFAULT_URL_OPTIONS if multitenant?

    @default_url_options ||= begin
      value = EncryptedConfig.find_by(key: EncryptedConfig::APP_URL_KEY)&.value if ENV['APP_URL'].blank?
      value ||= DEFAULT_APP_URL
      url = Addressable::URI.parse(value)
      { host: url.host, port: url.port, protocol: url.scheme }
    end
  end

  def product_name
    PRODUCT_NAME
  end

  # Upstream's upgrade offers and its console, licence, community and AI-help links. A single-tenant instance can take
  # an upstream licence through upstream's console; the shared multi-tenant instance runs no console, so its screens
  # leave them out, as upstream's iOS app does, and help points to SUPPORT_EMAIL.
  def upstream_offers?
    !multitenant?
  end

  # The app tour's words; its support step points to SUPPORT_EMAIL instead of upstream's AI help and address.
  def app_tour_i18n
    i18n = I18n.t('app_tour')

    upstream_offers? ? i18n : i18n.merge(support_description: "#{I18n.t('need_help_ask_a_question_')} #{SUPPORT_EMAIL}")
  end

  def refresh_default_url_options!
    @default_url_options = nil
  end
end
