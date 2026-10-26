# frozen_string_literal: true

# Public sign-up of a multi-tenant instance (ALLOW_SIGNUP=true); otherwise /sign_up does not exist.
class RegistrationsController < ApplicationController
  skip_before_action :maybe_redirect_to_setup
  skip_before_action :authenticate_user!
  skip_authorization_check

  before_action :ensure_signup_allowed!
  before_action :redirect_to_root_if_signed, if: :signed_in?

  def new
    @account = Account.new
    @user = @account.users.new(email: params.dig(:user, :email))
  end

  def create
    RateLimit.call("sign_up:#{request.remote_ip}", limit: 10, ttl: 1.hour)

    @account = Account.new(account_params)
    @account.timezone = Accounts.normalize_timezone(@account.timezone)
    @user = @account.users.new(user_params)

    @account.errors.add(:name, :blank) if @account.name.blank?

    return render :new, status: :unprocessable_content if @account.errors.any? || !@user.save

    Accounts.create_initial_configs(@account)

    sign_in(@user)

    redirect_to root_path
  end

  private

  def ensure_signup_allowed!
    render 'errors/404', status: :not_found, layout: false unless Docuseal.signup_allowed?
  end

  def redirect_to_root_if_signed
    redirect_to root_path, notice: I18n.t('you_are_already_signed_in')
  end

  def user_params
    return {} unless params[:user]

    params.require(:user).permit(:first_name, :last_name, :email, :password)
  end

  def account_params
    return {} unless params[:account]

    params.require(:account).permit(:name, :timezone, :locale)
  end
end
