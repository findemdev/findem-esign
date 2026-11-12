# frozen_string_literal: true

# The platform's app bar (its workspace menu and credits) in the signed-in top bar: framed from the platform the sign-in
# hand-off is configured for, allowed by the page's frame policy, and absent wherever there is no platform or no session.
describe 'Platform app bar', :multitenant do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }

  before do
    Accounts.create_initial_configs(account)
    create(:template, account:, author: user)
  end

  def frame_sources
    response.headers['Content-Security-Policy'][/frame-src ([^;]*)/, 1].to_s.split
  end

  context 'with a platform' do
    before do
      stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => 'platform-token-123'))
      stub_const('Docuseal::PLATFORM_SIGN_IN_URL', 'https://platform.example.test/people/sign?source=sign')
    end

    it 'frames the bar from the platform on signed-in pages, after the settings link and before the account menu' do
      sign_in(user)

      ['/', '/settings/profile', '/submissions'].each do |path|
        get path

        expect(response).to have_http_status(:ok), path

        bar = Nokogiri::HTML(response.body).at_css('.studio-topbar studio-app-bar')

        expect(bar).to be_present, path
        expect(bar['data-src']).to eq('https://platform.example.test/embed/app-bar?app=sign')
        expect(bar['data-title']).to eq('Workspace and credits')
        expect(bar.previous_element.at_css('#account_settings_button')).to be_present
        expect(bar.next_element['class']).to include('dropdown')
        expect(frame_sources).to eq(["'self'", 'https://platform.example.test'])
      end
    end

    it 'shows no bar on a signed-out page' do
      get '/sign_in', params: { local: '1' }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('studio-app-bar')
    end

    it 'shows no bar when the configured address is not one a browser should frame' do
      sign_in(user)

      ['http://platform.example.test/people/sign', 'https://user:pass@platform.example.test/people/sign', 'not a url',
       'javascript:alert(1)'].each do |entry|
        stub_const('Docuseal::PLATFORM_SIGN_IN_URL', entry)

        get '/'

        expect(response.body).not_to include('studio-app-bar'), entry
        expect(frame_sources).to eq(["'self'"]), entry
      end
    end
  end

  it 'shows no bar and allows no outside frame without a platform' do
    stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))
    sign_in(user)

    get '/'

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('studio-app-bar')
    expect(frame_sources).to eq(["'self'"])
  end
end
