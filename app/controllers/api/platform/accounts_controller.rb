# frozen_string_literal: true

module Api
  module Platform
    # Tenant accounts for the platform that runs this instance: create, or re-key by external_id.
    # Guarded by PLATFORM_API_TOKEN; without it the route answers 404.
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

      def create
        Params::PlatformAccountValidator.call(params)

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

        return head :not_found if token.blank?

        provided = request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1].to_s

        return if ActiveSupport::SecurityUtils.secure_compare(provided, token)

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

        account.users.active.find_by(email:) ||
          account.users.create!(email:, password: SecureRandom.hex, role: User::ADMIN_ROLE,
                                confirmed_at: Time.current)
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
