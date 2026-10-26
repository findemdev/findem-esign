# frozen_string_literal: true

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
end
