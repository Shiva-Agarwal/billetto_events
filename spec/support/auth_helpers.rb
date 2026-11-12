module AuthHelpers
  def session_token_for(user_id) = ClerkAuth::FakeAdapter.token_for(user_id)

  def auth_headers(user_id)
    { "Authorization" => "Bearer #{session_token_for(user_id)}", "Accept" => "application/json" }
  end

  # Request specs: authenticate exactly like clerk-js does in the browser (the __session cookie).
  def sign_in_with_cookie(user_id)
    cookies[ClerkAuth::SESSION_COOKIE] = session_token_for(user_id)
  end
end
