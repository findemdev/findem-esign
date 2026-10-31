# frozen_string_literal: true

describe 'Platform entry', :multitenant do
  let(:entry) { 'https://platform.example.test/people/sign?source=sign' }
  let!(:user) { create(:user) }

  before do
    stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => 'platform-token-123', 'FINDEM_SIGN_ENTRY_URL' => entry))
  end

  it 'routes the home, dashboard and protected pages through the platform with the requested path' do
    ['/', '/dashboard', '/templates?folder=2', '/settings/account', '/submissions'].each do |path|
      get path

      expect(response).to redirect_to(PlatformEntry.url_for(path))
      expect(URI.decode_www_form(URI.parse(response.location).query).to_h)
        .to eq('source' => 'sign', 'next' => path)
    end
  end

  it 'routes direct sign-in visits through the configured platform' do
    get '/sign_in'

    expect(response).to redirect_to(PlatformEntry.url_for('/'))
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.headers['Referrer-Policy']).to eq('no-referrer')
  end

  it 'preserves a safe return path when entering from sign-in' do
    get '/sign_in', params: { next: '/templates?folder=2' }

    expect(response).to redirect_to(PlatformEntry.url_for('/templates?folder=2'))
  end

  it 'refuses external return paths from sign-in' do
    get '/sign_in', params: { next: '//other.example.test' }

    expect(response).to redirect_to(PlatformEntry.url_for('/'))
  end

  it 'keeps explicit local sign-in reachable, including a failed password attempt' do
    get '/sign_in', params: { local: '1' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('user[password]')

    post '/sign_in', params: { user: { email: user.email, password: 'incorrect' } }

    expect(response.location.to_s).not_to start_with(entry)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('user[password]')
  end

  it 'does not redirect a signed-in user through the platform' do
    sign_in user
    get '/templates'

    expect(response).to have_http_status(:ok)

    get '/sign_in'

    expect(response).to redirect_to('/')
  end

  it 'links the workspace back to the configured platform origin without handoff parameters' do
    sign_in user
    get '/templates'

    expect(response.body).to include('data-theme="studio"')
    expect(response.body).to include('href="https://platform.example.test/"')
    expect(PlatformEntry.home_url).to eq('https://platform.example.test/')
  end

  it 'preserves local authentication and the product landing without a configured entry' do
    stub_const('ENV', ENV.to_h.except('FINDEM_SIGN_ENTRY_URL'))

    get '/templates'

    expect(response).to redirect_to('/sign_in')

    get '/sign_in'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('user[password]')

    get '/'

    expect(response).to redirect_to(Docuseal::PRODUCT_URL)
  end

  it 'requires a platform token and a valid web entry' do
    stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))

    expect(PlatformEntry.url_for('/')).to be_nil

    get '/sign_in'

    expect(response).to have_http_status(:ok)
  end

  it 'keeps unauthenticated JSON requests out of the browser redirect flow' do
    get '/templates', headers: { 'Accept' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
    expect(response.location).to be_nil
  end

  it 'replaces an existing next parameter and refuses external landing paths' do
    stub_const('ENV', ENV.to_h.merge('FINDEM_SIGN_ENTRY_URL' => "#{entry}&next=/old"))

    url = URI.parse(PlatformEntry.url_for('//other.example.test'))

    expect(URI.decode_www_form(url.query)).to eq([%w[source sign], ['next', '/']])
  end

  it 'ignores invalid entry configuration' do
    ['//platform.example.test', 'javascript:alert(1)', 'http://platform.example.test',
     'https://user:password@platform.example.test', 'https://platform.example.test/#fragment'].each do |invalid|
      stub_const('ENV', ENV.to_h.merge('FINDEM_SIGN_ENTRY_URL' => invalid))

      expect(PlatformEntry.url_for('/')).to be_nil
      expect(PlatformEntry.home_url).to be_nil
    end
  end
end
