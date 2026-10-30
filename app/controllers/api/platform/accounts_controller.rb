# frozen_string_literal: true

module Api
  module Platform
    # Tenant accounts for the platform that runs this instance: create, or re-key by external_id.
    # The optional ATS credential is restricted to its external_id namespace before every operation.
    class AccountsController < ActionController::API
      wrap_parameters false

      before_action :authenticate_platform!

      rescue_from Params::BaseValidator::InvalidParameterError,
                  ActionDispatch::Http::Parameters::ParseError do |e|
        render json: { error: e.message }, status: :unprocessable_content
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: e.record.errors.full_messages.first }, status: :unprocessable_content
      end

      rescue_from Docuseal::InvalidAtsPlatformConfiguration do
        render json: { error: 'Platform configuration is unavailable' }, status: :service_unavailable
      end

      def create
        Params::PlatformAccountValidator.call(params)

        if @ats_platform && !params[:external_id].to_s.match?(/\Afindem-ats:[A-Za-z0-9_.:-]{1,244}\z/)
          return render json: { error: 'Not authorized' }, status: :forbidden
        end

        account = Account.find_by(external_id: params[:external_id])
        created = account.nil?

        user, api_token =
          ApplicationRecord.transaction do
            account ||= create_account
            user = find_or_create_user(account)

            upsert_webhook(account) if params[:webhook].present?

            [user, rotate_token(user)]
          end

        render json: { account_id: account.id, user_id: user.id, api_token: },
               status: created ? :created : :ok
      end

      private

      def authenticate_platform!
        token = Docuseal.platform_api_token
        ats_token = Docuseal.ats_platform_api_token

        return head :not_found if token.blank? && ats_token.blank?

        if token.present? && ats_token.present? && ActiveSupport::SecurityUtils.secure_compare(token, ats_token)
          raise Docuseal::InvalidAtsPlatformConfiguration, 'ATS platform configuration is invalid'
        end

        provided = request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1].to_s

        if ats_token.present? && ActiveSupport::SecurityUtils.secure_compare(provided, ats_token)
          @ats_platform = true

          return
        end

        return if token.present? && ActiveSupport::SecurityUtils.secure_compare(provided, token)

        render json: { error: 'Not authenticated' }, status: :unauthorized
      end

      def create_account
        account = Account.create!(external_id: params[:external_id],
                                  name: params[:name],
                                  timezone: Accounts.normalize_timezone(params[:timezone].presence || 'UTC'),
                                  locale: params[:locale].presence || 'en-US')

        Accounts.create_initial_configs(account)

        account
      end

      def find_or_create_user(account)
        email = params[:email].to_s.strip.downcase

        user = account.users.active.find_by(email:) ||
               account.users.create!(email:, password: SecureRandom.hex, role: User::ADMIN_ROLE,
                                     confirmed_at: Time.current)

        stand_for_tenant(user, account)

        user
      end

      # The user stands for the tenant, not a person: signers see the tenant's name as the sender, and the completed and
      # declined notices stay off (the platform hears of those by webhook; the address is its own, not a person's).
      def stand_for_tenant(user, account)
        user.update!(first_name: account.name, last_name: nil) if user.full_name != account.name

        [UserConfig::RECEIVE_COMPLETED_EMAIL, UserConfig::RECEIVE_DECLINED_EMAIL].each do |key|
          user.user_configs.find_or_initialize_by(key:).update!(value: false)
        end
      end

      # The raw token is returned once; a repeat call rotates it, so the previous one stops working.
      def rotate_token(user)
        access_token = user.access_token
        access_token.update!(token: SecureRandom.base58(AccessToken::TOKEN_LENGTH))

        access_token.token
      end

      def upsert_webhook(account)
        webhook = params[:webhook]
        url = webhook[:url].to_s

        webhook_url = account.webhook_urls.find_or_initialize_by(sha1: Digest::SHA1.hexdigest(url))
        webhook_url.url = url
        webhook_url.secret = webhook[:secret].present? ? webhook.permit(secret: {})[:secret].to_h : {}
        webhook_url.events = webhook[:events] if webhook.key?(:events)
        webhook_url.save!
      end
    end
  end
end
