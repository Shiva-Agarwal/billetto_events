# Hosts Clerk's prebuilt <SignIn/> and <SignUp/> components (mounted by clerk-js).
class AuthController < ApplicationController
  def sign_in
    redirect_to root_path if signed_in?
  end

  def sign_up
    redirect_to root_path if signed_in?
  end

  private

  helper_method def after_auth_url
    url = params[:redirect_url].to_s
    url.start_with?("/") && !url.start_with?("//") ? url : root_path # no open redirects
  end
end
