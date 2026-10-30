# frozen_string_literal: true

require 'jwt'
require 'tmpdir'

describe 'Platform sign-in hand-off' do
  let(:platform_token) { 'platform-token-123' }
  let(:external_id) { '68fa0b2c1d2e3f4a5b6c7d8e' }
  let!(:account) { create(:account, external_id:) }
  let(:claimed) { Set.new }
  let(:now) { Time.current.to_i }
  let(:claims) do
    { iss: 'findem-people', aud: PlatformSessions::AUDIENCE, sub: 'u_jules', tenant: external_id,
      email: 'Jules@Northwind.test', name: 'Jules Rivera', role: 'admin', iat: now, exp: now + 60,
      jti: SecureRandom.base58(24) }
  end

  def token_for(payload = claims, key: PlatformSessions.key)
    JWT.encode(payload, key, 'HS256')
  end

  def signed_in_user_id
    session['warden.user.user.key']&.first&.first
  end

  before do
    stub_const('ENV', ENV.to_h.except('ATS_PLATFORM_CONFIG_FILE').merge('PLATFORM_API_TOKEN' => platform_token))
    allow(PlatformSessions).to receive(:claim_once) { |jti| claimed.add?(jti).present? }
  end

  it 'does not exist without PLATFORM_API_TOKEN' do
    stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))

    get '/platform/session', params: { token: token_for }

    expect(response).to have_http_status(:not_found)
  end

  it 'signs a new person in as an administrator of their organisation and lands on next' do
    expect do
      get '/platform/session', params: { token: token_for, next: '/templates/new' }
    end.to change(User, :count).by(1)

    user = account.users.find_by!(email: 'jules@northwind.test')

    expect(user).to have_attributes(first_name: 'Jules', last_name: 'Rivera', role: User::ADMIN_ROLE)
    expect(response).to redirect_to('/templates/new')
    expect(signed_in_user_id).to eq(user.id)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.headers['Referrer-Policy']).to eq('no-referrer')
  end

  it 'welcomes a new person to Findem Sign on the dashboard' do
    create(:template, account:, author: create(:user, account:))

    get '/platform/session', params: { token: token_for }
    get '/'

    expect(response.body).to include('Welcome to Findem Sign')
    expect(response.body).not_to include('Welcome to DocuSeal')
  end

  it 'signs in with the token the People gateway mints for fixed inputs' do
    # firstcut mcp_svc/hcm/esign_session.spec.ts produces this exact token.
    token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJmaW5kZW0tcGVvcGxlIiwiYXVkIjoiZmluZGVtLXNpZ24tc2V' \
            'zc2lvbiIsInN1YiI6IjY0YTAwMDAwMDAwMDAwMDAwMDAwMDAwMSIsInRlbmFudCI6IjY4ZmEwYjJjMWQyZTNmNGE1YjZjN2Q' \
            '4ZSIsImVtYWlsIjoianVsZXNAbm9ydGh3aW5kLnRlc3QiLCJuYW1lIjoiSnVsZXMgUml2ZXJhIiwicm9sZSI6ImFkbWluIiw' \
            'iaWF0IjoxNzkzMzc2MDAwLCJleHAiOjE3OTMzNzYwNjAsImp0aSI6Imp0aS0wMTIzNDU2Nzg5YWJjZGVmZ2hpaiJ9.qnmEg2' \
            'AA6QVyO_sbhEu0yZref4gx0MexkEY_srKOShM'

    travel_to(Time.zone.at(1_793_376_010)) { get('/platform/session', params: { token: }) }

    expect(response).to redirect_to('/')
    expect(account.users.find_by!(email: 'jules@northwind.test'))
      .to have_attributes(first_name: 'Jules', last_name: 'Rivera')
  end

  it 'signs in a person who already has a user in the account' do
    user = create(:user, account:, email: 'jules@northwind.test')

    expect { get '/platform/session', params: { token: token_for } }.not_to change(User, :count)

    expect(response).to redirect_to('/')
    expect(signed_in_user_id).to eq(user.id)
  end

  it 'refuses a token used twice' do
    token = token_for

    get('/platform/session', params: { token: })

    expect(response).to have_http_status(:found)

    get('/platform/session', params: { token: })

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to include('This sign-in link has expired', 'Open Findem Sign again')
  end

  it 'refuses an expired, forged, long-lived or misaddressed token' do
    [
      token_for(claims.merge(iat: now - 120, exp: now - 60)),
      token_for(key: OpenSSL::HMAC.digest('SHA256', 'another-token', PlatformSessions::KEY_LABEL)),
      token_for(claims.merge(exp: now + 3600)),
      token_for(claims.merge(aud: 'findem-hiring-session')),
      token_for(claims.except(:jti)),
      'not-a-token'
    ].each do |token|
      get('/platform/session', params: { token: })

      expect(response).to have_http_status(:unauthorized)
    end

    expect(account.users.count).to eq(0)
    expect(signed_in_user_id).to be_nil
  end

  it 'refuses an organisation without an account' do
    get '/platform/session', params: { token: token_for(claims.merge(tenant: 'org_unknown')) }

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('no Findem Sign account yet', 'Back to Findem Studio')
  end

  it 'refuses an email that signs in to another account' do
    create(:user, account: create(:account), email: 'jules@northwind.test')

    expect { get '/platform/session', params: { token: token_for } }.not_to change(User, :count)

    expect(response).to have_http_status(:conflict)
    expect(signed_in_user_id).to be_nil
  end

  it 'lands only on a path of this site' do
    {
      '//evil.example/x' => '/',
      'https://evil.example/x' => '/',
      '/api/templates' => '/',
      '/%61pi/templates' => '/',
      '/templates/../api' => '/',
      '/%2f%2fevil.example' => '/',
      '/%5cevil.example' => '/',
      '/templates%0a' => '/',
      '/templates%ff' => '/',
      "/templates\n" => '/',
      '/templates?folder=2' => '/templates?folder=2'
    }.each do |next_path, landing|
      get '/platform/session', params: { token: token_for(claims.merge(jti: SecureRandom.base58(24))), next: next_path }

      expect(response).to redirect_to(landing)
    end
  end

  it 'offers Sign in with Findem Studio on the sign-in page of a platform instance only' do
    create(:user, account:)

    get '/sign_in'

    expect(response.body).to include('Sign in with Findem Studio', Docuseal::PLATFORM_SIGN_IN_URL)

    stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))

    get '/sign_in'

    expect(response.body).not_to include('Sign in with Findem Studio')
  end

  context 'with a scoped ATS provisioning credential' do
    let(:ats_token) { 'synthetic-ats-platform-token' }
    let(:directory) { Dir.mktmpdir('ats-platform-session-') }
    let(:config_path) { File.join(directory, 'config.json') }
    let(:ats_key) { OpenSSL::HMAC.digest('SHA256', ats_token, PlatformSessions::KEY_LABEL) }

    before do
      File.write(config_path, { platform_token: ats_token }.to_json)
      File.chmod(0o400, config_path)
      stub_const('ENV', ENV.to_h.merge('ATS_PLATFORM_CONFIG_FILE' => config_path))
    end

    after { FileUtils.remove_entry(directory) }

    it 'continues to accept a session signed by the unrestricted platform credential' do
      get '/platform/session', params: { token: token_for }

      expect(response).to redirect_to('/')
      expect(signed_in_user_id).to eq(account.users.find_by!(email: 'jules@northwind.test').id)
    end

    it 'rejects an ATS-signed session before consuming its nonce or creating a user' do
      expect { get '/platform/session', params: { token: token_for(key: ats_key) } }.not_to change(User, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(signed_in_user_id).to be_nil
      expect(claimed).to be_empty
    end

    it 'does not enable browser sessions with only the scoped credential configured' do
      stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))

      get '/platform/session', params: { token: token_for(key: ats_key) }

      expect(response).to have_http_status(:not_found)
      expect(signed_in_user_id).to be_nil
      expect(claimed).to be_empty
    end

    it 'fails closed when the scoped and unrestricted credentials are equal' do
      stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => ats_token))

      expect { get '/platform/session', params: { token: token_for(key: ats_key) } }.not_to change(User, :count)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include('Findem Sign is temporarily unavailable')
      expect(response.body).not_to include(ats_token)
      expect(signed_in_user_id).to be_nil
      expect(claimed).to be_empty
    end

    it 'fails closed for a missing or malformed configured ATS file' do
      token = token_for
      File.chmod(0o600, config_path)
      File.write(config_path, '{private-invalid-config')
      File.chmod(0o400, config_path)

      [config_path, File.join(directory, 'missing.json')].each do |path|
        stub_const('ENV', ENV.to_h.merge('ATS_PLATFORM_CONFIG_FILE' => path))

        expect { get '/platform/session', params: { token: } }.not_to change(User, :count)

        expect(response).to have_http_status(:service_unavailable)
        expect(response.body).not_to include('private-invalid-config')
        expect(signed_in_user_id).to be_nil
        expect(claimed).to be_empty
      end
    end
  end
end
