# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Docuseal do
  describe '.signup_allowed?' do
    it 'is closed by default' do
      stub_const('ENV', ENV.to_h.except('MULTITENANT', 'ALLOW_SIGNUP'))

      expect(described_class.signup_allowed?).to be(false)
    end

    it 'opens with MULTITENANT=true and ALLOW_SIGNUP=true' do
      stub_const('ENV', ENV.to_h.merge('MULTITENANT' => 'true', 'ALLOW_SIGNUP' => 'true'))

      expect(described_class.signup_allowed?).to be(true)
    end

    it 'stays closed on a single-tenant instance' do
      stub_const('ENV', ENV.to_h.except('MULTITENANT').merge('ALLOW_SIGNUP' => 'true'))

      expect(described_class.signup_allowed?).to be(false)
    end
  end

  describe '.platform_api_token' do
    it 'is nil when unset or blank' do
      stub_const('ENV', ENV.to_h.except('PLATFORM_API_TOKEN'))

      expect(described_class.platform_api_token).to be_nil

      stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => ' '))

      expect(described_class.platform_api_token).to be_nil
    end

    it 'returns the token' do
      stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => 'secret'))

      expect(described_class.platform_api_token).to eq('secret')
    end
  end

  describe '.ats_platform_api_token' do
    let(:directory) { Dir.mktmpdir('ats-platform-config-') }
    let(:path) { File.join(directory, 'config.json') }
    let(:token) { 'synthetic-ats-platform-token' }

    before do
      File.write(path, { platform_token: token }.to_json)
      File.chmod(0o400, path)
      stub_const('ENV', ENV.to_h.merge('ATS_PLATFORM_CONFIG_FILE' => path))
    end

    after { FileUtils.remove_entry(directory) }

    it 'reads only the separately mounted token' do
      stub_const('ENV', ENV.to_h.merge('PLATFORM_API_TOKEN' => 'different-global-token'))

      expect(described_class.ats_platform_api_token).to eq(token)
      expect(described_class.platform_api_token).to eq('different-global-token')
    end

    it 'stays absent when the file is not configured, without using the global token' do
      stub_const('ENV', ENV.to_h.except('ATS_PLATFORM_CONFIG_FILE').merge('PLATFORM_API_TOKEN' => token))

      expect(described_class.ats_platform_api_token).to be_nil
    end

    it 'rejects missing, relative and symlink paths with a fixed error' do
      link = File.join(directory, 'link.json')
      File.symlink(path, link)

      [File.join(directory, 'missing.json'), 'relative.json', link].each do |invalid_path|
        stub_const('ENV', ENV.to_h.merge('ATS_PLATFORM_CONFIG_FILE' => invalid_path))

        expect { described_class.ats_platform_api_token }
          .to raise_error(Docuseal::InvalidAtsPlatformConfiguration, 'ATS platform configuration is invalid')
      end
    end

    it 'rejects permissions or ownership broader than the service secret contract' do
      File.chmod(0o644, path)

      expect { described_class.ats_platform_api_token }.to raise_error(Docuseal::InvalidAtsPlatformConfiguration)

      File.chmod(0o400, path)
      allow(Process).to receive(:euid).and_return(Process.euid + 1)

      expect { described_class.ats_platform_api_token }.to raise_error(Docuseal::InvalidAtsPlatformConfiguration)
    end

    it 'rejects empty, malformed, oversized or extra-key documents without exposing their content' do
      invalid = ['', '{private-json', '[]', '{}', { platform_token: 123 }.to_json,
                 { platform_token: 'short' }.to_json, { platform_token: "#{token}\n" }.to_json,
                 { platform_token: token, shared_secret: 'private-extra-field' }.to_json, ' ' * 8193]

      invalid.each do |bytes|
        File.chmod(0o600, path)
        File.write(path, bytes)
        File.chmod(0o400, path)

        expect { described_class.ats_platform_api_token }
          .to raise_error(Docuseal::InvalidAtsPlatformConfiguration, 'ATS platform configuration is invalid')
      end
    end
  end
end
