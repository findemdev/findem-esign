# frozen_string_literal: true

# The platform's sign-in hand-off (GET /platform/session): a person signed in on the platform that runs this instance
# opens their tenant's account here without a password. The platform signs a single-use, 60-second HS256 token with a
# key derived from PLATFORM_API_TOKEN, which it already holds (that token can already create and re-key every account).
module PlatformSessions
  AUDIENCE = 'findem-sign-session'
  KEY_LABEL = 'findem-sign/session/v1'
  TTL = 60
  NEXT_MAX = 512

  Refused = Class.new(StandardError) do
    attr_reader :status

    def initialize(status)
      @status = status
      super(status.to_s)
    end
  end

  module_function

  def key
    OpenSSL::HMAC.digest('SHA256', Docuseal.platform_api_token.to_s, KEY_LABEL)
  end

  # The token's claims, once: a bad signature, audience or lifetime, an expired or reused token is refused as unauthorized.
  def verify!(token)
    require 'jwt'

    claims, = JWT.decode(token.to_s, key, true, algorithm: 'HS256', aud: AUDIENCE, verify_aud: true,
                                                required_claims: %w[exp iat jti sub tenant email])

    raise Refused, :unauthorized if claims['exp'].to_i - claims['iat'].to_i > TTL
    raise Refused, :unauthorized unless claim_once(claims['jti'].to_s)

    claims
  rescue JWT::DecodeError
    raise Refused, :unauthorized
  end

  def claim_once(jti)
    return false if jti.blank?

    Sidekiq.redis { |conn| conn.call('SET', "platform_session:#{jti}", '1', 'NX', 'EX', TTL * 2) } == 'OK'
  end

  # The person in their tenant's account: an active user with the token's email, or a new administrator. An email that
  # already signs in to another account is refused rather than moved.
  def user_for!(claims)
    account = Account.active.find_by(external_id: claims['tenant'].to_s)

    raise Refused, :not_found unless account

    email = claims['email'].to_s.strip.downcase
    user = User.find_by(email:)

    raise Refused, :conflict if user && user.account_id != account.id
    raise Refused, :forbidden if user&.archived_at?

    user || create_user(account, email, claims['name'].to_s)
  end

  def create_user(account, email, name)
    first_name, last_name = name.strip.split(/\s+/, 2)

    account.users.create!(email:, first_name:, last_name:, role: User::ADMIN_ROLE,
                          password: SecureRandom.base58(32), confirmed_at: Time.current)
  rescue ActiveRecord::RecordInvalid
    raise Refused, :unauthorized
  end

  # A path on this site, never another origin or the API; anything else lands on the home page.
  def next_path(value)
    path = value.to_s

    return '/' if path.empty? || path.length > NEXT_MAX || !path.start_with?('/') || path.start_with?('//') ||
                  path.include?('\\') || path.match?(/[[:cntrl:]]/)

    uri = URI.parse(path)
    decoded = URI::DEFAULT_PARSER.unescape(uri.path)

    return '/' if uri.host || uri.scheme || decoded == '/api' || decoded.start_with?('/api/') ||
                  uri.path.match?(/%2f|%5c/i) || decoded.match?(/[[:cntrl:]]/) ||
                  decoded.split('/').intersect?(%w[. ..])

    path
  rescue URI::InvalidURIError, ArgumentError
    '/'
  end
end
