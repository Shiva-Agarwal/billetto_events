module ApplicationHelper
  def current_user_label
    return unless signed_in?

    Identity::User.find_by(clerk_user_id: current_user_id)&.display_name || current_user_id
  end

  def flash_class(type)
    type.to_s == "alert" ? "flash flash--alert" : "flash flash--notice"
  end
end
